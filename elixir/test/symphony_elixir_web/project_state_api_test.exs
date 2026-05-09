defmodule SymphonyElixirWeb.ProjectStateApiTest do
  use SymphonyElixir.TestSupport, async: false

  import Phoenix.ConnTest
  import Plug.Conn, only: [put_req_header: 3]

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

  test "GET /api/v1/projects/:project_id/log returns JSON for known project" do
    conn = get(build_conn(), "/api/v1/projects/default/log")
    body = json_response(conn, 200)
    assert body["project_id"] == "default"
    assert body["source"] in ["daemon_log_filtered", "project_file", "project_file_missing"]
    assert is_list(body["lines"])
  end

  test "GET /api/v1/projects/:project_id/log returns 404 for unknown project" do
    unknown = "missing-log-proj-#{System.unique_integer([:positive])}"
    conn = get(build_conn(), "/api/v1/projects/#{unknown}/log")
    assert json_response(conn, 404)["error"]["code"] == "project_not_found"
  end

  test "GET /api/v1/projects/:project_id/events returns 404 for unknown project" do
    unknown = "missing-events-proj-#{System.unique_integer([:positive])}"
    conn = get(build_conn(), "/api/v1/projects/#{unknown}/events")
    assert json_response(conn, 404)["error"]["code"] == "project_not_found"
  end

  test "GET /api/v1/projects lists default project with agent counts" do
    conn = get(build_conn(), "/api/v1/projects")
    body = json_response(conn, 200)
    assert is_list(body["projects"])

    default =
      Enum.find(body["projects"], &(&1["project_id"] == "default")) ||
        flunk("expected default project in listing")

    assert default["status"] in ["running", "starting", "stopped", "error"]
    assert default["counts"]["running"] >= 0
    assert default["counts"]["retrying"] >= 0
    assert default["counts"]["completed"] >= 0
  end

  test "POST /api/v1/projects/:id/refresh returns 404 for unknown project" do
    id = "missing-project-#{System.unique_integer([:positive])}"
    conn = post(build_conn(), "/api/v1/projects/#{id}/refresh", %{})
    assert json_response(conn, 404)["error"]["code"] == "project_not_found"
  end

  test "DELETE /api/v1/projects/:id/issues/:identifier returns 404 when issue is not active" do
    ident = "NOT-ACTIVE-#{System.unique_integer([:positive])}"
    conn = delete(build_conn(), "/api/v1/projects/default/issues/#{ident}")
    assert json_response(conn, 404)["error"]["code"] == "issue_not_found"
  end

  test "PUT /api/v1/projects/:id/issues/:identifier returns 400 when state is missing" do
    conn =
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> put("/api/v1/projects/default/issues/WEB-1", Jason.encode!(%{}))

    assert json_response(conn, 400)["error"]["code"] == "invalid_body"
  end

  test "POST /api/v1/projects rejects non-GET with 405" do
    conn = post(build_conn(), "/api/v1/projects", %{})
    assert json_response(conn, 405)["error"]["code"] == "method_not_allowed"
  end

  test "POST /api/v1/projects/:id/issues/:identifier returns 404 for unknown project" do
    id = "missing-project-#{System.unique_integer([:positive])}"
    conn = post(build_conn(), "/api/v1/projects/#{id}/issues/WEB-1", %{})
    assert json_response(conn, 404)["error"]["code"] == "project_not_found"
  end

  test "PUT /api/v1/projects/:id/issues/:identifier returns 404 for unknown project" do
    id = "missing-project-#{System.unique_integer([:positive])}"

    conn =
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> put("/api/v1/projects/#{id}/issues/WEB-1", Jason.encode!(%{"state" => "Todo"}))

    assert json_response(conn, 404)["error"]["code"] == "project_not_found"
  end

  test "DELETE /api/v1/projects/:id/issues/:identifier returns 404 for unknown project" do
    id = "missing-project-#{System.unique_integer([:positive])}"
    conn = delete(build_conn(), "/api/v1/projects/#{id}/issues/WEB-1")
    assert json_response(conn, 404)["error"]["code"] == "project_not_found"
  end

  test "legacy GET /api/v1/state still returns 200 in single-project test setup" do
    conn = get(build_conn(), "/api/v1/state")
    assert conn.status == 200
    body = json_response(conn, 200)
    assert Map.has_key?(body, "counts") or Map.has_key?(body, "error")
  end
end
