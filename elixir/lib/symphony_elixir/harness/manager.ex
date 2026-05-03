defmodule SymphonyElixir.Harness.Manager do
  @moduledoc """
  Detects WORKFLOW.md changes via SHA-256 hash comparison and dispatches harness
  agent sessions to reconfigure the project's `.agents/` definitions and skills.

  Manages `.symphony/harness-state.json` — a persistent marker recording the
  WORKFLOW.md content hash.

  Per SPEC V1.1 Section 4.4: on WORKFLOW.md change (hash mismatch), dispatches a
  harness agent session in the **project directory** (not a per-issue workspace).
  The harness agent does NOT consume an issue dispatch slot.
  """

  use GenServer
  require Logger

  alias SymphonyElixir.{CodingAgent, Workflow}

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
      :workflow_file_path
    ]
  end

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Returns true when a harness agent is currently running in the project directory.
  """
  @spec harness_running?() :: boolean()
  def harness_running? do
    case Process.whereis(__MODULE__) do
      pid when is_pid(pid) ->
        GenServer.call(__MODULE__, :harness_running?)

      _ ->
        false
    end
  end

  @doc """
  Synchronously check for WORKFLOW.md changes and dispatch if needed.
  Returns `:dispatched`, `:unchanged`, or `:harness_busy`.
  """
  @spec check() :: :dispatched | :unchanged | :harness_busy
  def check do
    GenServer.call(__MODULE__, :check)
  end

  @impl true
  def init(opts) do
    project_dir = Keyword.get(opts, :project_dir, File.cwd!())

    workflow_file_path =
      Keyword.get(opts, :workflow_file_path, Path.join(project_dir, "WORKFLOW.md"))

    harness_state_path = harness_state_path(project_dir)

    state = %State{
      project_dir: project_dir,
      harness_state_path: harness_state_path,
      last_hash: load_last_hash(harness_state_path),
      harness_running: false
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
    {:noreply, %{state | harness_running: false}}
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
    Logger.info("Harness agent process terminated")
    {:noreply, %{state | harness_running: false}}
  end

  def handle_info({ref, _result}, state) when is_reference(ref) do
    {:noreply, state}
  end

  defp do_check(state) do
    workflow_path = Map.get(state, :workflow_file_path) || Workflow.workflow_file_path()
    current_hash = compute_hash(workflow_path)

    if current_hash != state.last_hash do
      _ =
        Logger.info(
          "WORKFLOW.md hash changed last=#{inspect(state.last_hash)} current=#{inspect(current_hash)}; dispatching harness agent"
        )

      state = dispatch_harness_agent(state, current_hash)
      {:dispatched, state}
    else
      {:unchanged, state}
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

  defp dispatch_harness_agent(state, current_hash) do
    adapter = CodingAgent.adapter()
    prompt = build_harness_prompt(state.last_hash, current_hash)

    task_ref =
      Task.async(fn ->
        case adapter.start_session(state.project_dir, []) do
          {:ok, session} ->
            try do
              result = adapter.run_turn(session, prompt, @harness_issue, [])
              send(__MODULE__, {:harness_complete, result})
            after
              adapter.stop_session(session)
            end

          {:error, reason} ->
            Logger.error("Failed to start harness agent session: #{inspect(reason)}")
            send(__MODULE__, {:harness_complete, {:error, reason}})
        end
      end)

    Process.monitor(task_ref.pid)

    persist_hash(state.harness_state_path, current_hash)

    %{state | last_hash: current_hash, harness_running: true}
  end

  defp build_harness_prompt(nil, "") do
    "WORKFLOW.md is empty or does not exist. No harness configuration is needed."
  end

  defp build_harness_prompt(nil, _current_hash) do
    "setup a harness for the project according to WORKFLOW.md"
  end

  defp build_harness_prompt(_last_hash, "") do
    "WORKFLOW.md has been deleted. Clean up harness configuration accordingly."
  end

  defp build_harness_prompt(_last_hash, _current_hash) do
    "update an existing harness for the project according to the updated WORKFLOW.md"
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
