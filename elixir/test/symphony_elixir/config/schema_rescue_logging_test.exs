defmodule SymphonyElixir.Config.SchemaRescueLoggingTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.Config.Schema

  defp with_app_env(app, key, value, fun) do
    env = Application.get_all_env(app)
    had_key? = Keyword.has_key?(env, key)
    previous = Keyword.get(env, key)

    try do
      Application.put_env(app, key, value)
      fun.()
    after
      if had_key? do
        Application.put_env(app, key, previous)
      else
        Application.delete_env(app, key)
      end
    end
  end

  defp non_existing_atom_string do
    "symphony_web69_extra_disallowed_#{System.unique_integer([:positive])}"
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
    missing = non_existing_atom_string()
    assert_raise ArgumentError, fn -> String.to_existing_atom(missing) end

    root =
      Path.join(
        System.tmp_dir!(),
        "symphony-schema-warn-rescue-#{System.unique_integer([:positive])}"
      )

    log =
      capture_log(fn ->
        with_app_env(:symphony_elixir, :extra_disallowed_workflow_keys_for_test, [missing], fn ->
          assert {:ok, _} = Schema.parse(minimal_parse_config(root))
        end)
      end)

    assert log =~ "Config.Schema.warn_disallowed_keys"
    assert log =~ "ArgumentError"
  end

  test "strip_disallowed_keys rescue logs warning with error reason" do
    missing = non_existing_atom_string()
    assert_raise ArgumentError, fn -> String.to_existing_atom(missing) end

    root =
      Path.join(
        System.tmp_dir!(),
        "symphony-schema-strip-rescue-#{System.unique_integer([:positive])}"
      )

    log =
      capture_log(fn ->
        with_app_env(:symphony_elixir, :extra_disallowed_workflow_keys_for_test, [missing], fn ->
          assert {:ok, _} = Schema.parse(minimal_parse_config(root))
        end)
      end)

    assert log =~ "Config.Schema.strip_disallowed_keys"
    assert log =~ "ArgumentError"
  end
end
