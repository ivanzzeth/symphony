defmodule SymphonyElixir.OrchestratorGlobalDispatchTest do
  use ExUnit.Case, async: false

  alias SymphonyElixir.{Orchestrator, ProjectRegistry}

  defmodule CountingStub do
    @moduledoc false
    use GenServer

    @spec start_link(integer()) :: GenServer.on_start()
    def start_link(n) when is_integer(n), do: GenServer.start_link(__MODULE__, n)

    @impl true
    def init(n), do: {:ok, n}

    @impl true
    def handle_call(:running_sessions_count, _from, n), do: {:reply, n, n}
  end

  setup do
    prev = Application.get_env(:symphony_elixir, :daemon_max_global_agents_override)
    Application.put_env(:symphony_elixir, :daemon_max_global_agents_override, 3)

    on_exit(fn ->
      if prev == nil do
        Application.delete_env(:symphony_elixir, :daemon_max_global_agents_override)
      else
        Application.put_env(:symphony_elixir, :daemon_max_global_agents_override, prev)
      end
    end)

    :ok
  end

  test "global dispatch slot respects daemon.max_global_agents across ProjectRegistry peers" do
    stub_id = "global-cap-stub-#{System.unique_integer([:positive])}"
    {:ok, stub} = GenServer.start_link(CountingStub, 3)

    on_exit(fn ->
      _ = ProjectRegistry.unregister(stub_id)
      if Process.alive?(stub), do: GenServer.stop(stub)
    end)

    :ok = ProjectRegistry.register(stub_id, stub)

    state = %Orchestrator.State{
      running: %{},
      workflow_store: nil,
      task_supervisor: SymphonyElixir.TaskSupervisor,
      poll_interval_ms: 30_000,
      max_concurrent_agents: 10,
      next_poll_due_at_ms: 0,
      poll_check_in_progress: false,
      tick_timer_ref: nil,
      tick_token: nil,
      coding_agent_kind: "codex",
      completed: MapSet.new(),
      claimed: MapSet.new(),
      retry_attempts: %{},
      codex_totals: %{input_tokens: 0, output_tokens: 0, total_tokens: 0, seconds_running: 0},
      codex_rate_limits: nil,
      pending_agent_outcomes: %{},
      max_turns_halted_at: %{},
      project_id: "self-test"
    }

    refute Orchestrator.global_dispatch_slot_available_for_test?(state)

    :ok = ProjectRegistry.unregister(stub_id)
    assert Orchestrator.global_dispatch_slot_available_for_test?(state)
  end
end
