defmodule SymphonyElixir.MT99CodexCaptureSmokeTest do
  @moduledoc """
  Fast smoke path for MT-99: verifies `{:codex_worker_update, ...}` messages are
  integrated into running-entry fields, global `codex_totals`, and snapshot
  `rate_limits` without running the full orchestrator suite.
  """

  use SymphonyElixir.TestSupport

  test "smoke: codex updates capture session, token usage, and rate limits" do
    issue_id = "issue-mt-99-codex-smoke"

    issue = %Issue{
      id: issue_id,
      identifier: "MT-99",
      title: "Smoke test",
      description: "Capture codex updates",
      state: "In Progress",
      url: "https://example.org/issues/MT-99"
    }

    orchestrator_name = Module.concat(__MODULE__, :MT99SmokeOrchestrator)
    {:ok, pid} = Orchestrator.start_link(name: orchestrator_name)

    on_exit(fn ->
      if Process.alive?(pid) do
        Process.exit(pid, :normal)
      end
    end)

    initial_state = :sys.get_state(pid)
    process_ref = make_ref()
    started_at = DateTime.utc_now()

    running_entry = %{
      pid: self(),
      ref: process_ref,
      identifier: issue.identifier,
      issue: issue,
      session_id: nil,
      turn_count: 0,
      last_codex_message: nil,
      last_codex_timestamp: nil,
      last_codex_event: nil,
      codex_input_tokens: 0,
      codex_output_tokens: 0,
      codex_total_tokens: 0,
      codex_last_reported_input_tokens: 0,
      codex_last_reported_output_tokens: 0,
      codex_last_reported_total_tokens: 0,
      started_at: started_at
    }

    :sys.replace_state(pid, fn _ ->
      initial_state
      |> Map.put(:running, %{issue_id => running_entry})
      |> Map.put(:claimed, MapSet.put(initial_state.claimed, issue_id))
    end)

    now = DateTime.utc_now()

    send(
      pid,
      {:codex_worker_update, issue_id,
       %{
         event: :session_started,
         session_id: "thread-mt-99-smoke",
         timestamp: now
       }}
    )

    send(
      pid,
      {:codex_worker_update, issue_id,
       %{
         event: :notification,
         payload: %{
           "method" => "thread/tokenUsage/updated",
           "params" => %{
             "tokenUsage" => %{
               "total" => %{"inputTokens" => 10, "outputTokens" => 3, "totalTokens" => 13}
             }
           }
         },
         timestamp: now,
         codex_app_server_pid: "99199"
       }}
    )

    rate_limits = %{
      "limit_id" => "codex",
      "primary" => %{"remaining" => 90, "limit" => 100},
      "secondary" => nil,
      "credits" => %{"has_credits" => false, "unlimited" => false, "balance" => nil}
    }

    send(
      pid,
      {:codex_worker_update, issue_id,
       %{
         event: :notification,
         payload: %{
           "method" => "codex/event/token_count",
           "params" => %{
             "msg" => %{
               "type" => "event_msg",
               "payload" => %{
                 "type" => "token_count",
                 "rate_limits" => rate_limits
               }
             }
           }
         },
         timestamp: now
       }}
    )

    snapshot = GenServer.call(pid, :snapshot)
    assert %{running: [entry]} = snapshot
    assert entry.issue_id == issue_id
    assert entry.session_id == "thread-mt-99-smoke"
    assert entry.turn_count == 1
    assert entry.codex_app_server_pid == "99199"
    assert entry.codex_input_tokens == 10
    assert entry.codex_output_tokens == 3
    assert entry.codex_total_tokens == 13
    assert entry.last_codex_event == :notification
    assert snapshot.rate_limits == rate_limits

    send(pid, {:DOWN, process_ref, :process, self(), :normal})
    completed = :sys.get_state(pid)
    assert completed.codex_totals.input_tokens == 10
    assert completed.codex_totals.output_tokens == 3
    assert completed.codex_totals.total_tokens == 13
  end
end
