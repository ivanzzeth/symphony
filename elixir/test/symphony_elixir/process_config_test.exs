defmodule SymphonyElixir.ProcessConfigTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias SymphonyElixir.ProcessConfig

  setup do
    tmp_yaml =
      Path.join(
        System.tmp_dir!(),
        "symphony-test-config-#{System.unique_integer([:positive])}.yaml"
      )

    on_exit(fn -> File.rm(tmp_yaml) end)
    {:ok, tmp_yaml: tmp_yaml}
  end

  describe "load/1 with no file" do
    setup do
      # Isolate from the real ~/.config/symphony/symphony.yaml
      previous_cfg = System.get_env("SYMPHONY_CONFIG_PATH")
      System.put_env("SYMPHONY_CONFIG_PATH", "/nonexistent/symphony-for-test.yaml")
      on_exit(fn -> restore_env("SYMPHONY_CONFIG_PATH", previous_cfg) end)
      :ok
    end

    test "returns defaults when no config file exists" do
      assert {:ok, config} = ProcessConfig.load("/nonexistent/path/symphony.yaml")
      assert config.server.host == "127.0.0.1"
      assert is_nil(config.server.port)
      assert config.observability.dashboard_enabled == true
      assert config.observability.refresh_ms == 1_000
      assert config.observability.render_interval_ms == 16
      assert config.daemon.max_global_agents == nil
      assert config.projects == []
    end

    test "returns defaults when nil path is given" do
      assert {:ok, config} = ProcessConfig.load(nil)
      assert config.server.host == "127.0.0.1"
      assert config.daemon.max_global_agents == nil
      assert config.projects == []
    end
  end

  describe "load/1 with yaml file" do
    test "reads server.port from yaml file", %{tmp_yaml: tmp_yaml} do
      write_yaml(tmp_yaml, %{"server" => %{"port" => 4000}})

      assert {:ok, config} = ProcessConfig.load(tmp_yaml)
      assert config.server.port == 4000
      assert config.server.host == "127.0.0.1"
    end

    test "reads server.host from yaml file", %{tmp_yaml: tmp_yaml} do
      write_yaml(tmp_yaml, %{"server" => %{"host" => "0.0.0.0"}})

      assert {:ok, config} = ProcessConfig.load(tmp_yaml)
      assert config.server.host == "0.0.0.0"
    end

    test "reads observability settings from yaml file", %{tmp_yaml: tmp_yaml} do
      write_yaml(tmp_yaml, %{
        "observability" => %{
          "dashboard_enabled" => false,
          "refresh_ms" => 500,
          "render_interval_ms" => 32
        }
      })

      assert {:ok, config} = ProcessConfig.load(tmp_yaml)
      refute config.observability.dashboard_enabled
      assert config.observability.refresh_ms == 500
      assert config.observability.render_interval_ms == 32
    end

    test "reads daemon.max_global_agents from yaml file", %{tmp_yaml: tmp_yaml} do
      write_yaml(tmp_yaml, %{"daemon" => %{"max_global_agents" => 7}})

      assert {:ok, config} = ProcessConfig.load(tmp_yaml)
      assert config.daemon.max_global_agents == 7
    end

    test "ignores non-positive daemon.max_global_agents values", %{tmp_yaml: tmp_yaml} do
      write_yaml(tmp_yaml, %{"daemon" => %{"max_global_agents" => 0}})

      assert {:ok, config} = ProcessConfig.load(tmp_yaml)
      assert is_nil(config.daemon.max_global_agents)
    end

    test "rejects invalid port values from yaml (returns nil)", %{tmp_yaml: tmp_yaml} do
      write_yaml(tmp_yaml, %{"server" => %{"port" => -5}})

      assert {:ok, config} = ProcessConfig.load(tmp_yaml)
      assert is_nil(config.server.port)
    end

    test "handles empty yaml file gracefully", %{tmp_yaml: tmp_yaml} do
      File.write!(tmp_yaml, "")

      assert {:ok, config} = ProcessConfig.load(tmp_yaml)
      assert config.server.host == "127.0.0.1"
      assert config.daemon.max_global_agents == nil
      assert config.projects == []
    end
  end

  describe "config file path resolution" do
    test "uses cli --config arg when provided" do
      assert ProcessConfig.config_path("/custom/path.yaml") == "/custom/path.yaml"
    end

    test "falls back to env var when no cli arg" do
      previous = System.get_env("SYMPHONY_CONFIG_PATH")
      System.put_env("SYMPHONY_CONFIG_PATH", "/env/path.yaml")

      on_exit(fn -> restore_env("SYMPHONY_CONFIG_PATH", previous) end)

      assert ProcessConfig.config_path(nil) == "/env/path.yaml"
    end

    test "falls back to ~/.config/symphony/symphony.yaml when nothing else set" do
      previous = System.get_env("SYMPHONY_CONFIG_PATH")
      System.delete_env("SYMPHONY_CONFIG_PATH")

      on_exit(fn -> restore_env("SYMPHONY_CONFIG_PATH", previous) end)

      expected = Path.join(System.user_home!(), ".config/symphony/symphony.yaml")
      assert ProcessConfig.config_path(nil) == expected
    end
  end

  describe "priority resolution: CLI > env > yaml > defaults" do
    test "CLI --port overrides yaml port", %{tmp_yaml: tmp_yaml} do
      Application.put_env(:symphony_elixir, :server_port_override, 9999)

      on_exit(fn -> Application.delete_env(:symphony_elixir, :server_port_override) end)

      write_yaml(tmp_yaml, %{"server" => %{"port" => 4000}})
      assert {:ok, config} = ProcessConfig.load(tmp_yaml)
      assert config.server.port == 9999
    end

    test "SYMPHONY_PORT env overrides yaml port", %{tmp_yaml: tmp_yaml} do
      previous = System.get_env("SYMPHONY_PORT")
      System.put_env("SYMPHONY_PORT", "5555")

      on_exit(fn -> restore_env("SYMPHONY_PORT", previous) end)

      write_yaml(tmp_yaml, %{"server" => %{"port" => 4000}})
      assert {:ok, config} = ProcessConfig.load(tmp_yaml)
      assert config.server.port == 5555
    end

    test "SYMPHONY_HOST env overrides yaml host", %{tmp_yaml: tmp_yaml} do
      previous = System.get_env("SYMPHONY_HOST")
      System.put_env("SYMPHONY_HOST", "10.0.0.1")

      on_exit(fn -> restore_env("SYMPHONY_HOST", previous) end)

      write_yaml(tmp_yaml, %{"server" => %{"host" => "127.0.0.1"}})
      assert {:ok, config} = ProcessConfig.load(tmp_yaml)
      assert config.server.host == "10.0.0.1"
    end
  end

  defp write_yaml(tmp_yaml, map) do
    yaml = encode_yaml(map)
    File.write!(tmp_yaml, yaml)
  end

  defp encode_yaml(map) when is_map(map) do
    map
    |> Enum.map(fn {key, val} ->
      if is_map(val) do
        "#{key}:\n#{indent(encode_yaml(val), 2)}"
      else
        "#{key}: #{String.trim(encode_yaml(val))}\n"
      end
    end)
    |> Enum.join()
  end

  defp encode_yaml(val) when is_integer(val), do: Integer.to_string(val)
  defp encode_yaml(val) when is_boolean(val), do: Atom.to_string(val)
  defp encode_yaml(val) when is_binary(val), do: ~s("#{val}")

  defp encode_yaml(val) when is_map(val) do
    val
    |> Enum.map(fn {key, val2} ->
      "  #{key}: #{String.trim(encode_yaml(val2))}"
    end)
    |> Enum.join("\n")
  end

  defp indent(str, spaces) do
    padding = String.duplicate(" ", spaces)
    str |> String.split("\n", trim: true) |> Enum.map(&(padding <> &1)) |> Enum.join("\n")
  end

  describe "Config.server_port/0 convenience function" do
    setup do
      previous_cfg = System.get_env("SYMPHONY_CONFIG_PATH")
      System.put_env("SYMPHONY_CONFIG_PATH", "/nonexistent/symphony-for-test.yaml")
      original_store_state = save_and_replace_store_with_defaults()

      on_exit(fn ->
        restore_env("SYMPHONY_CONFIG_PATH", previous_cfg)
        restore_store_state(original_store_state)
      end)

      :ok
    end

    test "reads from SYMPHONY_PORT env var when no CLI override set" do
      previous = System.get_env("SYMPHONY_PORT")
      System.put_env("SYMPHONY_PORT", "6000")

      on_exit(fn -> restore_env("SYMPHONY_PORT", previous) end)

      assert SymphonyElixir.Config.server_port() == 6000
    end

    test "CLI override takes precedence over env var" do
      Application.put_env(:symphony_elixir, :server_port_override, 7777)

      on_exit(fn -> Application.delete_env(:symphony_elixir, :server_port_override) end)

      previous = System.get_env("SYMPHONY_PORT")
      System.put_env("SYMPHONY_PORT", "6000")

      on_exit(fn -> restore_env("SYMPHONY_PORT", previous) end)

      assert SymphonyElixir.Config.server_port() == 7777
    end

    test "falls back to nil when nothing is configured" do
      previous_port = System.get_env("SYMPHONY_PORT")

      on_exit(fn -> restore_env("SYMPHONY_PORT", previous_port) end)

      System.delete_env("SYMPHONY_PORT")

      Application.delete_env(:symphony_elixir, :server_port_override)

      assert is_nil(SymphonyElixir.Config.server_port())
    end
  end

  describe "Config.server_host/0 convenience function" do
    setup do
      previous_cfg = System.get_env("SYMPHONY_CONFIG_PATH")
      System.put_env("SYMPHONY_CONFIG_PATH", "/nonexistent/symphony-for-test.yaml")
      original_store_state = save_and_replace_store_with_defaults()

      on_exit(fn ->
        restore_env("SYMPHONY_CONFIG_PATH", previous_cfg)
        restore_store_state(original_store_state)
      end)

      :ok
    end

    test "reads from SYMPHONY_HOST env var when no CLI override set" do
      previous = System.get_env("SYMPHONY_HOST")
      System.put_env("SYMPHONY_HOST", "10.0.0.1")

      on_exit(fn -> restore_env("SYMPHONY_HOST", previous) end)

      assert SymphonyElixir.Config.server_host() == "10.0.0.1"
    end

    test "CLI override takes precedence over env var" do
      Application.put_env(:symphony_elixir, :server_host_override, "192.168.1.1")

      on_exit(fn -> Application.delete_env(:symphony_elixir, :server_host_override) end)

      previous = System.get_env("SYMPHONY_HOST")
      System.put_env("SYMPHONY_HOST", "10.0.0.1")

      on_exit(fn -> restore_env("SYMPHONY_HOST", previous) end)

      assert SymphonyElixir.Config.server_host() == "192.168.1.1"
    end

    test "falls back to default host when nothing is configured" do
      previous_host = System.get_env("SYMPHONY_HOST")

      on_exit(fn -> restore_env("SYMPHONY_HOST", previous_host) end)

      System.delete_env("SYMPHONY_HOST")
      Application.delete_env(:symphony_elixir, :server_host_override)

      assert SymphonyElixir.Config.server_host() == "127.0.0.1"
    end
  end

  defp save_and_replace_store_with_defaults do
    store_pid = Process.whereis(SymphonyElixir.ProcessConfig.Store)

    if store_pid do
      original = :sys.get_state(store_pid)

      defaults = %SymphonyElixir.ProcessConfig{
        server: %{port: nil, host: "127.0.0.1"},
        observability: %{dashboard_enabled: true, refresh_ms: 1_000, render_interval_ms: 16},
        projects: []
      }

      :sys.replace_state(store_pid, fn _state -> defaults end)
      original
    end
  end

  defp restore_store_state(nil), do: :ok

  defp restore_store_state(%{} = state) do
    store_pid = Process.whereis(SymphonyElixir.ProcessConfig.Store)

    if store_pid do
      :sys.replace_state(store_pid, fn _state -> state end)
    end
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)

  defp yaml_trim(heredoc) when is_binary(heredoc), do: String.trim_leading(heredoc)

  describe "load/1 projects (multi-project symphony.yaml)" do
    test "parses enabled projects with workflow paths relative to config file" do
      dir =
        Path.join(
          System.tmp_dir!(),
          "symphony-mp-#{System.unique_integer([:positive])}"
        )

      File.mkdir_p!(dir)

      wf_a = Path.join(dir, "WORKFLOW_A.md")
      wf_b = Path.join(dir, "WORKFLOW_B.md")
      ws_a = Path.join(dir, "workspace_a")
      ws_b = Path.join(dir, "workspace_b")
      File.mkdir_p!(ws_a)
      File.mkdir_p!(ws_b)

      write_min_workflow!(wf_a, ws_a)
      write_min_workflow!(wf_b, ws_b)

      yaml_path = Path.join(dir, "symphony.yaml")

      File.write!(
        yaml_path,
        yaml_trim("""
        projects:
          alpha:
            workflow: WORKFLOW_A.md
          beta:
            workflow: WORKFLOW_B.md
            enabled: false
        """)
      )

      on_exit(fn -> File.rm_rf(dir) end)

      assert {:ok, config} = ProcessConfig.load(yaml_path)
      assert [p1, p2] = Enum.sort_by(config.projects, & &1.id)
      assert p1.id == "alpha"
      assert p1.workflow_path == wf_a
      assert p1.enabled == true
      assert p2.id == "beta"
      assert p2.workflow_path == wf_b
      assert p2.enabled == false
    end

    test "returns error when workflow file is missing" do
      dir =
        Path.join(
          System.tmp_dir!(),
          "symphony-mp-missing-#{System.unique_integer([:positive])}"
        )

      File.mkdir_p!(dir)
      yaml_path = Path.join(dir, "symphony.yaml")

      File.write!(
        yaml_path,
        yaml_trim("""
        projects:
          only:
            workflow: ./nope.md
        """)
      )

      on_exit(fn -> File.rm_rf(dir) end)

      assert {:error, {:invalid_symphony_yaml, msg}} = ProcessConfig.load(yaml_path)
      assert msg =~ "workflow file not found"
    end

    test "returns error when enabled has wrong type" do
      dir =
        Path.join(
          System.tmp_dir!(),
          "symphony-mp-bool-#{System.unique_integer([:positive])}"
        )

      File.mkdir_p!(dir)
      wf = Path.join(dir, "W.md")
      write_min_workflow!(wf, Path.join(dir, "ws"))
      yaml_path = Path.join(dir, "symphony.yaml")

      File.write!(
        yaml_path,
        yaml_trim("""
        projects:
          bad:
            workflow: W.md
            enabled: "yes"
        """)
      )

      on_exit(fn -> File.rm_rf(dir) end)

      assert {:error, {:invalid_symphony_yaml, msg}} = ProcessConfig.load(yaml_path)
      assert msg =~ "enabled must be a boolean"
    end

    test "warns when two projects share the same resolved workspace.root" do
      dir =
        Path.join(
          System.tmp_dir!(),
          "symphony-mp-coll-#{System.unique_integer([:positive])}"
        )

      File.mkdir_p!(dir)
      shared = Path.join(dir, "same_ws")
      File.mkdir_p!(shared)

      wf1 = Path.join(dir, "WF1.md")
      wf2 = Path.join(dir, "WF2.md")
      write_min_workflow!(wf1, shared)
      write_min_workflow!(wf2, shared)

      yaml_path = Path.join(dir, "symphony.yaml")

      File.write!(
        yaml_path,
        yaml_trim("""
        projects:
          one:
            workflow: WF1.md
          two:
            workflow: WF2.md
        """)
      )

      on_exit(fn -> File.rm_rf(dir) end)

      log =
        capture_log(fn ->
          assert {:ok, config} = ProcessConfig.load(yaml_path)
          assert length(config.projects) == 2
        end)

      assert log =~ "workspace.root collision"
      assert log =~ "one"
      assert log =~ "two"
    end
  end

  defp write_min_workflow!(path, workspace_root) when is_binary(workspace_root) do
    root_esc = String.replace(workspace_root, "\\", "/")

    File.write!(path, """
    ---
    workspace:
      root: "#{root_esc}"
    agent:
      command: cursor --model auto
    tracker:
      kind: memory
    ---

    test prompt
    """)
  end

  describe "apply_symphony_project_cli_overrides/2 and load/2 :symphony_project_cli_overrides" do
    test "merges dotted workflow override before validation", %{tmp_yaml: tmp_yaml} do
      dir = Path.dirname(tmp_yaml)
      File.mkdir_p!(dir)
      wf = Path.join(dir, "REAL.md")
      ws = Path.join(dir, "ws_o")
      File.mkdir_p!(ws)
      write_min_workflow!(wf, ws)

      File.write!(
        tmp_yaml,
        yaml_trim("""
        projects:
          svc:
            workflow: ./MISSING.md
        """)
      )

      overrides = [{"svc.workflow", wf}]

      assert {:ok, config} =
               ProcessConfig.load(tmp_yaml,
                 skip_overrides: true,
                 symphony_project_cli_overrides: overrides
               )

      assert [%{id: "svc", workflow_path: ^wf, enabled: true}] = config.projects
    end

    test "returns clear error for invalid override path" do
      assert {:error, {:invalid_symphony_yaml, msg}} =
               ProcessConfig.load(nil,
                 skip_overrides: true,
                 symphony_project_cli_overrides: [{"only_one_segment", "x"}]
               )

      assert msg =~ "CLI --project"
      assert msg =~ "expected <project-id>.<field>"
    end
  end
end
