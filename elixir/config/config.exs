import Config

config :phoenix, :json_library, Jason

config :symphony_elixir, SymphonyElixirWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  url: [host: "localhost"],
  render_errors: [
    formats: [html: SymphonyElixirWeb.ErrorHTML, json: SymphonyElixirWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: SymphonyElixir.PubSub,
  live_view: [signing_salt: "symphony-live-view"],
  secret_key_base: String.duplicate("s", 64),
  check_origin: false,
  server: false

# Mix 1.19+ runs `app.start` before `test/test_helper.exs`, so SYMPHONY_CONFIG_PATH
# set only in test_helper is too late for ProcessConfig.Store / HttpServer. Use a
# committed fixture so tests do not inherit ~/.config/symphony/symphony.yaml and
# collide on the default HTTP port.
if config_env() == :test do
  config :symphony_elixir, :config_arg,
    Path.expand("../test/fixtures/symphony_process_minimal.yaml", __DIR__)
end
