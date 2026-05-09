defmodule SymphonyElixirWeb.ProjectObservabilityController do
  @moduledoc """
  Per-project observability: SSE event stream and log tail API.
  """

  use Phoenix.Controller, formats: [:json]

  alias Plug.Conn
  alias SymphonyElixir.{Config, LogFile, ProjectLogTail, ProjectRegistry}
  alias SymphonyElixirWeb.ObservabilityPubSub

  @default_log_lines 500
  @max_log_lines 10_000
  @sse_keepalive_ms 25_000

  @spec events(Conn.t(), map()) :: Conn.t()
  def events(conn, %{"project_id" => project_id}) when is_binary(project_id) do
    case authorize_project(project_id) do
      :ok ->
        :ok = ObservabilityPubSub.subscribe(project_id)

        conn =
          conn
          |> put_resp_header("cache-control", "no-cache")
          |> put_resp_content_type("text/event-stream")
          |> send_chunked(200)

        try do
          case chunk(conn, ": connected\n\n") do
            {:ok, conn} ->
              sse_loop(conn, project_id)

            {:error, _} ->
              conn
          end
        after
          :ok = ObservabilityPubSub.unsubscribe(project_id)
        end

      {:error, :not_found} ->
        error_response(conn, 404, "project_not_found", "Unknown project_id")
    end
  end

  @spec log(Conn.t(), map()) :: Conn.t()
  def log(conn, %{"project_id" => project_id} = params) when is_binary(project_id) do
    case authorize_project(project_id) do
      :ok ->
        n = parse_line_limit(Map.get(params, "n") || Map.get(params, "lines"))
        {lines, source} = read_project_log(project_id, n)
        json(conn, %{project_id: project_id, source: source, lines: lines})

      {:error, :not_found} ->
        error_response(conn, 404, "project_not_found", "Unknown project_id")
    end
  end

  defp authorize_project(project_id) do
    case ProjectRegistry.lookup(project_id) do
      {:ok, _} -> :ok
      :error -> {:error, :not_found}
    end
  end

  defp sse_loop(conn, project_id) do
    receive do
      :observability_updated ->
        payload =
          Jason.encode!(%{
            type: "observability_updated",
            project_id: project_id
          })

        case chunk(conn, "event: observability\ndata: #{payload}\n\n") do
          {:ok, conn} ->
            sse_loop(conn, project_id)

          {:error, _} ->
            conn
        end
    after
      @sse_keepalive_ms ->
        case chunk(conn, ": keep-alive\n\n") do
          {:ok, conn} ->
            sse_loop(conn, project_id)

          {:error, _} ->
            conn
        end
    end
  end

  defp parse_line_limit(nil), do: @default_log_lines

  defp parse_line_limit(raw) when is_binary(raw) do
    case Integer.parse(String.trim(raw)) do
      {n, ""} when n > 0 -> min(n, @max_log_lines)
      _ -> @default_log_lines
    end
  end

  defp parse_line_limit(_), do: @default_log_lines

  defp read_project_log(project_id, n) do
    obs = Config.observability()

    if Map.get(obs, :per_project_log_files, false) do
      path = LogFile.project_log_file(project_id)

      if File.regular?(path) do
        {ProjectLogTail.tail_lines(path, n), "project_file"}
      else
        {[], "project_file_missing"}
      end
    else
      main = Application.get_env(:symphony_elixir, :log_file, LogFile.default_log_file()) |> Path.expand()

      lines =
        if File.regular?(main) do
          main
          |> ProjectLogTail.tail_lines(n * 50)
          |> Enum.filter(&log_line_matches_project?(&1, project_id))
          |> Enum.take(-n)
        else
          []
        end

      {lines, "daemon_log_filtered"}
    end
  end

  defp log_line_matches_project?(line, project_id) when is_binary(line) do
    String.contains?(line, "project_id=#{project_id}") or
      String.contains?(line, "[project_id: #{project_id}]") or
      String.contains?(line, "project_id: #{project_id}")
  end

  defp error_response(conn, status, code, message) do
    conn
    |> put_status(status)
    |> json(%{error: %{code: code, message: message}})
  end
end
