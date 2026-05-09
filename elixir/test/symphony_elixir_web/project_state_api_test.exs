defmodule SymphonyElixirWeb.ProjectStateApiTest do
  use SymphonyElixir.TestSupport, async: false

  import Phoenix.ConnTest

  alias SymphonyElixir.Orchestrator

  @endpoint SymphonyElixirWeb.Endpoint

  setup do
    orch = Orchestrator.whereis()
    refute is_nil(orch)

    prev_endpoint = Application.get_env(:symphony_elixir, SymphonyElixirWeb.Endpoint, [])

    endpoint_config =
      prev_endpoint
      |> Keyword.merge(
        server: false,
        secret_key_base: String.duplicate("s", 64),
        orchestrator: orch,
        snapshot_timeout_ms: 15_000
      )

    Application.put_env(:symphony_elixir, SymphonyElixirWeb.Endpoint, endpoint_config)
    start_supervised!({SymphonyElixirWeb.Endpoint, []})

    on_exit(fn ->
      Application.put_env(:symphony_elixir, SymphonyElixirWeb.Endpoint, prev_endpoint)
    end)

    :ok
  end

  test "GET /api/v1/projects/:project_id/state returns 404 for unknown project" do
    conn = get(build_conn(), "/api/v1/projects/does-not-exist-#{System.unique_integer([:positive])}/state")

    assert json_response(conn, 404)["error"]["code"] == "project_not_found"
  end

  test "GET /api/v1/projects/:project_id/state includes project_id for default project" do
    conn = get(build_conn(), "/api/v1/projects/default/state")
    body = json_response(conn, 200)
    assert body["project_id"] == "default"
    assert body["counts"]["completed"] >= 0
  end
end
