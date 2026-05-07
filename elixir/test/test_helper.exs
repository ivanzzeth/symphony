# Isolate ExUnit from the parent shell's SYMPHONY_* exports (Config precedence)
# and from a developer-local ~/.config/symphony/symphony.yaml that binds :4000,
# which would make `mix test` fail with :eaddrinuse when a daemon already
# listens there. HttpServer stays disabled when process `server.port` is nil.
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
