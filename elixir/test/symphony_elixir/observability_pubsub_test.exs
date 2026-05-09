defmodule SymphonyElixir.ObservabilityPubSubTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixirWeb.ObservabilityPubSub

  test "subscribe and broadcast_update deliver dashboard updates" do
    assert :ok = ObservabilityPubSub.subscribe()
    assert :ok = ObservabilityPubSub.broadcast_update()
    assert_receive :observability_updated
  end

  test "broadcast_update only reaches subscribers on the same project topic" do
    parent = self()

    pid_a =
      spawn_link(fn ->
        :ok = ObservabilityPubSub.subscribe("pubsub-scope-a")
        send(parent, {:sub_ready, :a})

        receive do
          :observability_updated -> send(parent, {:a, :got})
        after
          400 -> send(parent, {:a, :timeout})
        end
      end)

    pid_b =
      spawn_link(fn ->
        :ok = ObservabilityPubSub.subscribe("pubsub-scope-b")
        send(parent, {:sub_ready, :b})

        receive do
          :observability_updated -> send(parent, {:b, :got})
        after
          400 -> send(parent, {:b, :timeout})
        end
      end)

    assert_receive {:sub_ready, :a}
    assert_receive {:sub_ready, :b}

    :ok = ObservabilityPubSub.broadcast_update("pubsub-scope-a")

    assert_receive {:a, :got}
    assert_receive {:b, :timeout}, 500

    Process.exit(pid_a, :kill)
    Process.exit(pid_b, :kill)
  end

  test "broadcast_update is a no-op when pubsub is unavailable" do
    pubsub_child_id = Phoenix.PubSub.Supervisor

    on_exit(fn ->
      if Process.whereis(SymphonyElixir.PubSub) == nil do
        assert {:ok, _pid} = Supervisor.restart_child(SymphonyElixir.Supervisor, pubsub_child_id)
      end
    end)

    assert is_pid(Process.whereis(SymphonyElixir.PubSub))
    assert :ok = Supervisor.terminate_child(SymphonyElixir.Supervisor, pubsub_child_id)
    refute Process.whereis(SymphonyElixir.PubSub)

    assert :ok = ObservabilityPubSub.broadcast_update()
  end
end
