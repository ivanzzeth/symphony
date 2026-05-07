# Isolate ExUnit from the parent shell's SYMPHONY_* exports (Config precedence).
# Mix 1.19+ starts the app before this file runs; early boot uses
# `config/config.exs` → `test/fixtures/symphony_process_minimal.yaml` via
# `:config_arg` so HttpServer does not read ~/.config/symphony/symphony.yaml first.
# When SYMPHONY_CONFIG_PATH is unset, also write a temp yaml for code paths that
# only consult the environment variable.
unless System.get_env("SYMPHONY_CONFIG_PATH") do
  path =
    Path.join(
      System.tmp_dir!(),
      "symphony-exunit-process-#{System.unique_integer([:positive])}.yaml"
    )

  File.write!(path, "observability:\n  dashboard_enabled: true\n")
  System.put_env("SYMPHONY_CONFIG_PATH", path)
end

System.delete_env("SYMPHONY_PORT")
System.delete_env("SYMPHONY_HOST")

ExUnit.start()
Code.require_file("support/snapshot_support.exs", __DIR__)
Code.require_file("support/test_support.exs", __DIR__)
