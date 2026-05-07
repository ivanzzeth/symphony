import Config

# Ensure process-level YAML does not inherit a developer machine's ~/.config/symphony
# server.port before the application boots. `test/test_helper.exs` runs after startup,
# so SYMPHONY_* must be established during test config evaluation.
System.delete_env("SYMPHONY_PORT")
System.delete_env("SYMPHONY_HOST")

if System.get_env("SYMPHONY_CONFIG_PATH") in [nil, ""] do
  default_path = Path.join(System.tmp_dir!(), "symphony-mix-test-process-config.yaml")
  File.write!(default_path, "observability:\n  dashboard_enabled: true\n")
  System.put_env("SYMPHONY_CONFIG_PATH", default_path)
end
