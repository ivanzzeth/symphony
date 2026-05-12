defmodule SymphonyElixir.Harness.Manager do
  @moduledoc """
  Detects WORKFLOW.md changes via SHA-256 hash comparison and dispatches harness
  agent sessions by creating a real Linear issue for the orchestrator to pick up.

  Manages `.symphony/harness-state.json` — a persistent marker recording the
  WORKFLOW.md content hash and the active harness Linear issue ID.

  On WORKFLOW.md change (hash mismatch):
    1. Creates a real Linear issue with harness prompt as its description
    2. Sets issue to Todo (or active state for dispatch)
    3. Orchestrator polls and picks it up naturally
    4. Agent runs in workspace, commits `.agents/` changes, creates PR
    5. Goes through In Review → Merging → Done
    6. Harness.Manager detects Done → records hash as processed
  """

  use GenServer
  require Logger

  alias SymphonyElixir.Workflow

  @harness_state_dir ".symphony"
  @harness_state_file "harness-state.json"
  @poll_interval_ms 10_000

  defmodule State do
    @moduledoc false
    defstruct [
      :project_dir,
      :project_id,
      :harness_state_path,
      :last_hash,
      :harness_issue_id,
      :harness_running,
      :poll_timer_ref,
      :workflow_file_path,
      :manager_pid,
      :workflow_store
    ]
  end

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Returns true when a harness agent is currently running.
  """
  @spec harness_running?(GenServer.server() | :auto) :: boolean()
  def harness_running?(server \\ :auto) do
    resolved = resolve_harness_server(server)

    try do
      if resolved, do: GenServer.call(resolved, :harness_running?), else: false
    catch
      :exit, _ -> false
    end
  end

  @doc """
  Synchronously check for WORKFLOW.md changes and dispatch if needed.
  Returns `:dispatched`, `:unchanged`, or `:harness_busy`.
  """
  @spec check(GenServer.server() | :auto) :: :dispatched | :unchanged | :harness_busy
  def check(server \\ :auto) do
    case resolve_harness_server(server) do
      nil -> :unchanged
      resolved -> GenServer.call(resolved, :check)
    end
  end

  defp resolve_harness_server(:auto) do
    case Application.get_env(:symphony_elixir, :primary_project_id) do
      id when is_binary(id) ->
        case Registry.lookup(SymphonyElixir.ProjectProcessRegistry, {id, :harness_manager}) do
          [{pid, _}] -> pid
          [] -> Process.whereis(__MODULE__)
        end

      _ ->
        Process.whereis(__MODULE__)
    end
  end

  defp resolve_harness_server(name), do: name

  @doc false
  @spec git_toplevel(Path.t()) :: Path.t()
  def git_toplevel(start_dir \\ File.cwd!()) do
    case System.cmd("git", ["-C", start_dir, "rev-parse", "--show-toplevel"], stderr_to_stdout: true) do
      {toplevel, 0} -> String.trim(toplevel)
      _ -> start_dir
    end
  end

  @impl true
  def init(opts) do
    project_dir =
      Keyword.get(opts, :project_dir, File.cwd!())
      |> git_toplevel()

    workflow_file_path =
      Keyword.get(opts, :workflow_file_path) ||
        if Application.get_env(:symphony_elixir, :workflow_file_path) do
          Workflow.workflow_file_path()
        else
          Path.join(project_dir, "WORKFLOW.md")
        end

    harness_state_path = harness_state_path(project_dir)
    {last_hash, harness_issue_id} = load_harness_state(harness_state_path)

    state = %State{
      project_dir: project_dir,
      project_id: Keyword.get(opts, :project_id),
      harness_state_path: harness_state_path,
      last_hash: last_hash,
      harness_issue_id: harness_issue_id,
      harness_running: harness_issue_id != nil,
      manager_pid: self(),
      workflow_store: Keyword.get(opts, :workflow_store)
    }

    state =
      state
      |> Map.put(:workflow_file_path, workflow_file_path)
      |> schedule_poll()

    {:ok, state}
  end

  @impl true
  def handle_call(:harness_running?, _from, state) do
    {:reply, state.harness_running, state}
  end

  def handle_call(:check, _from, %{harness_running: true} = state) do
    {:reply, :harness_busy, state}
  end

  def handle_call(:check, _from, state) do
    {reply, state} = do_check(state)
    {:reply, reply, state}
  end

  @impl true
  def handle_info(:poll, state) do
    state = schedule_poll(state)

    if state.harness_running do
      # Check if harness issue has reached a terminal state
      state = check_harness_issue_status(state)
      {:noreply, state}
    else
      {_reply, state} = do_check(state)
      {:noreply, state}
    end
  end

  defp do_check(state) do
    workflow_path = Map.get(state, :workflow_file_path) || Workflow.workflow_file_path()
    current_hash = compute_hash(workflow_path)

    if current_hash != state.last_hash do
      _ = Logger.info("WORKFLOW.md hash changed last=#{inspect(state.last_hash)} current=#{inspect(current_hash)}; creating harness Linear issue")

      state = dispatch_harness_agent(state, current_hash)
      {:dispatched, state}
    else
      {:unchanged, state}
    end
  end

  defp check_harness_issue_status(%State{harness_issue_id: nil} = state), do: state

  defp check_harness_issue_status(%State{harness_issue_id: issue_id} = state) do
    case fetch_linear_issue(issue_id) do
      {:ok, %{state: state_name}} when is_binary(state_name) ->
        normalized = String.downcase(String.trim(state_name))

        if normalized in ["done", "canceled", "duplicate"] do
          Logger.info("Harness issue #{issue_id} reached terminal state: #{state_name}; recording hash")

          # Re-read current WORKFLOW.md hash from disk instead of using
          # state.last_hash (which may be stale if the file changed during
          # harness execution). This prevents a cascade of duplicate harness
          # issues when WORKFLOW.md changes while a harness issue is active.
          workflow_path = Map.get(state, :workflow_file_path) || Workflow.workflow_file_path()
          current_hash = compute_hash(workflow_path)

          persist_harness_state(state.harness_state_path, current_hash, nil)

          %{state | last_hash: current_hash, harness_issue_id: nil, harness_running: false}
        else
          state
        end

      {:error, reason} ->
        Logger.debug("Failed to check harness issue #{issue_id} status: #{inspect(reason)}")
        state

      _ ->
        state
    end
  end

  defp compute_hash(path) do
    case File.read(path) do
      {:ok, content} ->
        content
        |> then(&:crypto.hash(:sha256, &1))
        |> Base.encode16(case: :lower)

      {:error, :enoent} ->
        ""

      {:error, reason} ->
        Logger.warning("Failed to read WORKFLOW.md for hash at #{path}: #{inspect(reason)}")
        nil
    end
  end

  defp load_harness_state(path) do
    case File.read(path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, decoded} ->
            hash = Map.get(decoded, "hash")
            issue_id = Map.get(decoded, "harness_issue_id")
            {hash, issue_id}

          _ ->
            {nil, nil}
        end

      {:error, :enoent} ->
        {nil, nil}

      {:error, reason} ->
        Logger.warning("Failed to read harness-state.json at #{path}: #{inspect(reason)}")
        {nil, nil}
    end
  end

  defp persist_harness_state(path, hash, issue_id) do
    state_dir = Path.dirname(path)
    File.mkdir_p!(state_dir)

    state = %{
      "hash" => hash,
      "harness_issue_id" => issue_id,
      "updated_at" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    File.write!(path, Jason.encode!(state, pretty: true))
  end

  defp dispatch_harness_agent(state, current_hash) do
    prompt = build_harness_prompt(state.last_hash, current_hash, state.workflow_file_path)

    case create_harness_issue(state, prompt) do
      {:ok, issue_id} ->
        Logger.info("Created harness Linear issue: #{issue_id}")

        persist_harness_state(state.harness_state_path, current_hash, issue_id)

        %{state | last_hash: current_hash, harness_issue_id: issue_id, harness_running: true}

      {:error, reason} ->
        Logger.error("Failed to create harness issue: #{inspect(reason)}")
        state
    end
  end

  defp create_harness_issue(state, prompt) do
    cfg =
      case state.workflow_store do
        nil -> SymphonyElixir.Config.settings!()
        ws -> SymphonyElixir.Config.settings!(workflow_store: ws)
      end

    tracker = cfg.tracker

    cond do
      is_nil(tracker.api_key) ->
        {:error, :missing_linear_api_token}

      is_nil(tracker.project_slug) ->
        {:error, :missing_linear_project_slug}

      tracker.kind != "linear" ->
        {:error, {:unsupported_tracker, tracker.kind}}

      true ->
        with {:ok, issue_id} <-
               SymphonyElixir.Linear.Client.create_issue(
                 tracker.project_slug,
                 "HARNESS: Reconfigure agent harness",
                 prompt
               ),
           :ok <- move_harness_issue_to_todo(issue_id, state) do
          {:ok, issue_id}
        end
    end
  end

  defp move_harness_issue_to_todo(issue_id, state) do
    case SymphonyElixir.Tracker.update_issue_state(issue_id, "Todo",
           workflow_store: state.workflow_store
         ) do
      :ok -> :ok
      {:error, reason} ->
        Logger.warning("Failed to move harness issue #{issue_id} to Todo: #{inspect(reason)}; orchestrator may not pick it up")
        :ok
    end
  end

  defp fetch_linear_issue(issue_id) do
    case SymphonyElixir.Linear.Client.fetch_issue_by_id(issue_id) do
      {:ok, issue} -> {:ok, %{state: issue.state}}
      other -> other
    end
  end

  @harness_setup_prompt """
  Use the /harness skill to build a new agent harness for this project.

  The workflow file is located at: __WORKFLOW_PATH__

  Read that file to understand the project's execution contract, then follow the full harness skill workflow (Phase 0-6) to analyze the domain, design the team architecture, generate agent definitions and skills, and register the harness context in AGENTS.md.

  IMPORTANT: Do NOT modify the workflow file under any circumstances. This file is the Symphony execution contract and must remain unchanged. Only create or update files under .agents/ and AGENTS.md.

  After completing the harness configuration:
  1. Commit all `.agents/` changes and AGENTS.md
  2. Push to origin
  3. Create a PR targeting the workflow's base branch
  """

  @harness_update_prompt """
  Use the /harness skill to reconfigure the agent harness for this project.

  The workflow file is located at: __WORKFLOW_PATH__

  That file has been updated. Read it to understand the changes, then follow the harness skill workflow — audit current .agents/ state (Phase 0), then determine which phases are needed to bring the harness in sync with the updated workflow file.

  IMPORTANT: Do NOT modify the workflow file under any circumstances. This file is the Symphony execution contract and must remain unchanged. Only create or update files under .agents/ and AGENTS.md.

  After completing the harness configuration:
  1. Commit all `.agents/` changes and AGENTS.md
  2. Push to origin
  3. Create a PR targeting the workflow's base branch
  """

  @harness_deletion_prompt """
  The workflow file at __WORKFLOW_PATH__ has been deleted. Use the /harness skill to clean up the agent harness configuration accordingly. Do NOT recreate the workflow file.

  After completing cleanup:
  1. Commit the changes
  2. Push to origin
  3. Create a PR targeting the workflow's base branch
  """

  @harness_empty_prompt "The workflow file at __WORKFLOW_PATH__ is empty or does not exist. No harness configuration is needed."

  defp build_harness_prompt(nil, "", path), do: inject_path(@harness_empty_prompt, path)
  defp build_harness_prompt(nil, _current_hash, path), do: inject_path(@harness_setup_prompt, path)
  defp build_harness_prompt(_last_hash, "", path), do: inject_path(@harness_deletion_prompt, path)
  defp build_harness_prompt(_last_hash, _current_hash, path), do: inject_path(@harness_update_prompt, path)

  defp inject_path(prompt, path), do: String.replace(prompt, "__WORKFLOW_PATH__", path)

  defp harness_state_path(project_dir) do
    Path.join([project_dir, @harness_state_dir, @harness_state_file])
  end

  defp schedule_poll(state) do
    if is_reference(state.poll_timer_ref) do
      Process.cancel_timer(state.poll_timer_ref)
    end

    timer_ref = Process.send_after(self(), :poll, @poll_interval_ms)
    %{state | poll_timer_ref: timer_ref}
  end
end
