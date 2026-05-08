import Config

# `mix test` starts the application before `test/test_helper.exs` runs, so the
# helper cannot set `SYMPHONY_CONFIG_PATH` early enough to avoid loading a
# developer `~/.config/symphony/symphony.yaml` that binds HttpServer (port
# conflicts / :eaddrinuse). Use a minimal process YAML with no `server:` block
# so `ProcessConfig` keeps `server.port` nil and HttpServer stays disabled until
# tests opt in via overrides.
path = Path.join(System.tmp_dir!(), "symphony-mix-test-process-config.yaml")
File.write!(path, "observability:\n  dashboard_enabled: true\n")
System.put_env("SYMPHONY_CONFIG_PATH", path)
System.delete_env("SYMPHONY_PORT")
System.delete_env("SYMPHONY_HOST")
