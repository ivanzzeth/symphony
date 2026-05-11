defmodule SymphonyElixir.Harness.Manager do
  @moduledoc """
  Detects WORKFLOW.md changes via SHA-256 hash comparison and dispatches harness
  agent sessions to reconfigure the project's `.agents/` definitions and skills.

  Manages `.symphony/harness-state.json` — a persistent marker recording the
  WORKFLOW.md content hash.

  Per SPEC V1.1 Section 4.4: on WORKFLOW.md change (hash mismatch), dispatches a
  harness agent session in the **project directory** (not a per-issue workspace).
  The harness agent does NOT consume an issue dispatch slot.

  When there is no stored hash yet and the workflow file is missing or
  effectively empty (including whitespace-only), the manager records the empty
  hash and **does not** start a harness session — there is nothing to configure.
  """

  use GenServer
  require Logger

  alias SymphonyElixir.{CodingAgent, Config.Context, Rescue, Workflow}

  @harness_state_dir ".symphony"
  @harness_state_file "harness-state.json"
  @poll_interval_ms 5_000

  @harness_issue %{
    id: "harness",
    identifier: "HARNESS",
    title: "Reconfigure agent harness",
    state: "harness"
  }

  defmodule State do
    @moduledoc false
    defstruct [
      :project_dir,
      :harness_state_path,
      :last_hash,
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
  Returns true when a harness agent is currently running in the project directory.
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

  Returns `:dispatched`, `:unchanged`, `:harness_busy`, or `:synced` (hash recorded
  for a missing or empty workflow with no prior harness baseline — harness agent
  not started).
  """
  @spec check(GenServer.server() | :auto) ::
          :dispatched | :unchanged | :harness_busy | :synced
  def check(server \\ :auto) do
    case resolve_harness_server(server) do
      nil ->
        :unchanged

      resolved ->
        GenServer.call(resolved, :check)
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
    workflow_store = Keyword.get(opts, :workflow_store)

    state = %State{
      project_dir: project_dir,
      harness_state_path: harness_state_path,
      last_hash: load_last_hash(harness_state_path),
      harness_running: false,
      manager_pid: self(),
      workflow_store: workflow_store
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
      {:noreply, state}
    else
      {_reply, state} = do_check(state)
      {:noreply, state}
    end
  end

  def handle_info({:harness_complete, _result}, state) do
    Logger.info("Harness agent session completed")
    {:noreply, sync_last_hash(%{state | harness_running: false})}
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
    Logger.info("Harness agent process terminated")
    {:noreply, sync_last_hash(%{state | harness_running: false})}
  end

  def handle_info({ref, _result}, state) when is_reference(ref) do
    {:noreply, state}
  end

  defp do_check(state) do
    workflow_path = Map.get(state, :workflow_file_path) || Workflow.workflow_file_path()
    current_hash = compute_hash(workflow_path)

    cond do
      current_hash == state.last_hash ->
        {:unchanged, state}

      skip_harness_for_empty_workflow?(state.last_hash, current_hash) ->
        _ =
          Logger.info(
            "WORKFLOW.md at #{workflow_path} is missing or effectively empty; recording hash and skipping harness agent dispatch"
          )

        persist_hash(state.harness_state_path, current_hash)
        {:synced, %{state | last_hash: current_hash}}

      true ->
        _ =
          Logger.info(
            "WORKFLOW.md hash changed last=#{inspect(state.last_hash)} current=#{inspect(current_hash)}; dispatching harness agent"
          )

        state = dispatch_harness_agent(state, current_hash)
        {:dispatched, state}
    end
  end

  defp skip_harness_for_empty_workflow?(last_hash, current_hash) do
    current_hash == "" and is_nil(last_hash)
  end

  defp compute_hash(path) do
    case File.read(path) do
      {:ok, content} ->
        if String.trim(content) == "" do
          ""
        else
          content
          |> then(&:crypto.hash(:sha256, &1))
          |> Base.encode16(case: :lower)
        end

      {:error, :enoent} ->
        ""

      {:error, reason} ->
        Logger.warning("Failed to read WORKFLOW.md for hash at #{path}: #{inspect(reason)}")
        nil
    end
  end

  defp load_last_hash(path) do
    case File.read(path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, %{"hash" => hash}} when is_binary(hash) -> hash
          _ -> nil
        end

      {:error, :enoent} ->
        nil

      {:error, reason} ->
        Logger.warning("Failed to read harness-state.json at #{path}: #{inspect(reason)}")
        nil
    end
  end

  defp persist_hash(path, hash) do
    state_dir = Path.dirname(path)
    File.mkdir_p!(state_dir)

    state = %{
      "hash" => hash,
      "updated_at" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    File.write!(path, Jason.encode!(state, pretty: true))
  end

  @harness_max_turns 3

  defp dispatch_harness_agent(state, current_hash) do
    prompt = build_harness_prompt(state.last_hash, current_hash, state.workflow_file_path)

    task_ref =
      Task.async(fn ->
        try do
          if ws = state.workflow_store do
            Context.put_workflow_store(ws)
          end

          adapter = CodingAgent.adapter()
          do_dispatch_harness(adapter, state, prompt)
        rescue
          e ->
            Rescue.log_error("Harness agent task crashed", e, __STACKTRACE__)
            send(state.manager_pid, {:harness_complete, {:error, e}})
        after
          _ = Context.delete_workflow_store()
        end
      end)

    Process.monitor(task_ref.pid)

    persist_hash(state.harness_state_path, current_hash)

    %{state | last_hash: current_hash, harness_running: true}
  end

  defp do_dispatch_harness(adapter, state, prompt) do
    manager_pid = state.manager_pid

    case adapter.start_session(state.project_dir, []) do
      {:ok, session} ->
        try do
          result = run_harness_turns(adapter, session, prompt)
          send(manager_pid, {:harness_complete, result})
        after
          adapter.stop_session(session)
        end

      {:error, reason} ->
        Logger.error("Failed to start harness agent session: #{inspect(reason)}")
        send(manager_pid, {:harness_complete, {:error, reason}})
    end
  end

  defp run_harness_turns(adapter, session, prompt) do
    do_run_harness_turns(adapter, session, prompt, 1, @harness_max_turns)
  end

  defp do_run_harness_turns(_adapter, session, _prompt, turn_number, max_turns)
       when turn_number > max_turns do
    Logger.info("Harness agent reached max_turns=#{max_turns}")
    {:ok, session}
  end

  defp do_run_harness_turns(adapter, session, prompt, turn_number, max_turns) do
    turn_prompt = if turn_number == 1, do: prompt, else: "Continue the harness configuration. Resume from the current workspace and .agents/ state."

    case adapter.run_turn(session, turn_prompt, @harness_issue, []) do
      {:ok, turn_result} ->
        Logger.info("Harness agent turn #{turn_number}/#{max_turns} completed")

        updated_session = Map.merge(session, %{resume_id: turn_result.resume_id})

        # Short sleep between turns to avoid rate limiting
        :timer.sleep(2_000)

        do_run_harness_turns(adapter, updated_session, prompt, turn_number + 1, max_turns)

      {:error, reason} ->
        Logger.error("Harness agent turn #{turn_number}/#{max_turns} failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @harness_setup_prompt """
  Use the /harness skill to build a new agent harness for this project.

  The workflow file is located at: __WORKFLOW_PATH__

  Read that file to understand the project's execution contract, then follow the full harness skill workflow (Phase 0-6) to analyze the domain, design the team architecture, generate agent definitions and skills, and register the harness context in AGENTS.md.

  IMPORTANT: Do NOT modify the workflow file under any circumstances. This file is the Symphony execution contract and must remain unchanged. Only create or update files under .agents/ and AGENTS.md.
  """

  @harness_update_prompt """
  Use the /harness skill to reconfigure the agent harness for this project.

  The workflow file is located at: __WORKFLOW_PATH__

  That file has been updated. Read it to understand the changes, then follow the harness skill workflow — audit current .agents/ state (Phase 0), then determine which phases are needed to bring the harness in sync with the updated workflow file.

  IMPORTANT: Do NOT modify the workflow file under any circumstances. This file is the Symphony execution contract and must remain unchanged. Only create or update files under .agents/ and AGENTS.md.
  """

  @harness_deletion_prompt """
  The workflow file at __WORKFLOW_PATH__ has been deleted. Use the /harness skill to clean up the agent harness configuration accordingly. Do NOT recreate the workflow file.
  """

  @harness_empty_prompt "The workflow file at __WORKFLOW_PATH__ is empty or does not exist. No harness configuration is needed."

  defp build_harness_prompt(nil, "", path), do: inject_path(@harness_empty_prompt, path)
  defp build_harness_prompt(nil, _current_hash, path), do: inject_path(@harness_setup_prompt, path)
  defp build_harness_prompt(_last_hash, "", path), do: inject_path(@harness_deletion_prompt, path)
  defp build_harness_prompt(_last_hash, _current_hash, path), do: inject_path(@harness_update_prompt, path)

  defp inject_path(prompt, path), do: String.replace(prompt, "__WORKFLOW_PATH__", path)

  defp sync_last_hash(state) do
    workflow_path = Map.get(state, :workflow_file_path) || Workflow.workflow_file_path()
    current_hash = compute_hash(workflow_path)
    persist_hash(state.harness_state_path, current_hash)
    %{state | last_hash: current_hash}
  end

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
