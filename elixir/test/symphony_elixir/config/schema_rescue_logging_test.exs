defmodule SymphonyElixir.Config.SchemaRescueLoggingTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.Config.Schema

  defp with_app_env(app, key, value, fun) do
    previous = Application.get_env(app, key)

    try do
      Application.put_env(app, key, value)
      fun.()
    after
      if previous == nil do
        Application.delete_env(app, key)
      else
        Application.put_env(app, key, previous)
      end
    end
  end

  defp minimal_parse_config(root) do
    %{
      "tracker" => %{"kind" => "memory"},
      "polling" => %{"interval_ms" => 30_000},
      "workspace" => %{"root" => root, "base_branch" => "main"},
      "worker" => %{},
      "agent" => %{"kind" => "codex", "command" => "codex app-server"},
      "codex" => %{"command" => "codex app-server"},
      "hooks" => %{}
    }
  end

  test "warn_disallowed_keys rescue logs warning with error reason" do
    root =
      Path.join(
        System.tmp_dir!(),
        "symphony-schema-warn-rescue-#{System.unique_integer([:positive])}"
      )

    log =
      capture_log(fn ->
        with_app_env(:symphony_elixir, :symphony_test_schema_warn_disallowed_raise, true, fn ->
          assert {:ok, _} = Schema.parse(minimal_parse_config(root))
        end)
      end)

    assert log =~ "Config.Schema.warn_disallowed_keys/1 failed, continuing:"
    assert log =~ "simulated warn_disallowed_keys failure"
  end

  test "strip_disallowed_keys rescue logs warning with error reason" do
    root =
      Path.join(
        System.tmp_dir!(),
        "symphony-schema-strip-rescue-#{System.unique_integer([:positive])}"
      )

    log =
      capture_log(fn ->
        with_app_env(:symphony_elixir, :symphony_test_schema_strip_disallowed_raise, true, fn ->
          assert {:ok, _} = Schema.parse(minimal_parse_config(root))
        end)
      end)

    assert log =~ "Config.Schema.strip_disallowed_keys/1 failed, returning raw config:"
    assert log =~ "simulated strip_disallowed_keys failure"
  end
end
