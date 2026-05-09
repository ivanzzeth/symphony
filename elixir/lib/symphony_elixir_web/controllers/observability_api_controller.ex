defmodule SymphonyElixirWeb.ObservabilityApiController do
  @moduledoc """
  JSON API for Symphony observability data.
  """

  use Phoenix.Controller, formats: [:json]

  alias Plug.Conn
  alias SymphonyElixir.{Orchestrator, ProjectAliases, ProjectRegistry}
  alias SymphonyElixirWeb.{Endpoint, Presenter}

  @spec state(Conn.t(), map()) :: Conn.t()
  def state(conn, _params) do
    json(conn, Presenter.state_payload(orchestrator(), snapshot_timeout_ms()))
  end

  @spec projects(Conn.t(), map()) :: Conn.t()
  def projects(conn, _params) do
    json(conn, Presenter.projects_payload(snapshot_timeout_ms()))
  end

  @spec project_state(Conn.t(), map()) :: Conn.t()
  def project_state(conn, %{"project_id" => project_id}) when is_binary(project_id) do
    case ProjectRegistry.lookup(project_id) do
      {:ok, orch_pid} ->
        json(conn, Presenter.project_state_payload(project_id, orch_pid, snapshot_timeout_ms()))

      :error ->
        error_response(conn, 404, "project_not_found", "Unknown project_id")
    end
  end

  @spec issue(Conn.t(), map()) :: Conn.t()
  def issue(conn, %{"issue_identifier" => issue_identifier}) do
    case Presenter.issue_payload(issue_identifier, orchestrator(), snapshot_timeout_ms()) do
      {:ok, payload} ->
        json(conn, payload)

      {:error, :issue_not_found} ->
        error_response(conn, 404, "issue_not_found", "Issue not found")
    end
  end

  @spec refresh(Conn.t(), map()) :: Conn.t()
  def refresh(conn, _params) do
    case Presenter.refresh_payload(orchestrator()) do
      {:ok, payload} ->
        conn
        |> put_status(202)
        |> json(payload)

      {:error, :unavailable} ->
        error_response(conn, 503, "orchestrator_unavailable", "Orchestrator is unavailable")
    end
  end

  @spec project_refresh(Conn.t(), map()) :: Conn.t()
  def project_refresh(conn, %{"project_id" => project_id}) when is_binary(project_id) do
    case ProjectRegistry.lookup(project_id) do
      {:ok, orch_pid} ->
        case Presenter.refresh_payload(orch_pid) do
          {:ok, payload} ->
            conn
            |> put_status(202)
            |> json(payload)

          {:error, :unavailable} ->
            error_response(conn, 503, "orchestrator_unavailable", "Orchestrator is unavailable")
        end

      :error ->
        error_response(conn, 404, "project_not_found", "Unknown project_id")
    end
  end

  @spec project_issue_dispatch(Conn.t(), map()) :: Conn.t()
  def project_issue_dispatch(conn, %{"project_id" => project_id, "identifier" => identifier})
      when is_binary(project_id) and is_binary(identifier) do
    case ProjectRegistry.lookup(project_id) do
      {:ok, orch_pid} ->
        case Orchestrator.manual_dispatch_issue(orch_pid, identifier) do
          :ok ->
            conn
            |> put_status(202)
            |> json(%{accepted: true, issue_identifier: identifier})

          {:error, :not_found} ->
            error_response(conn, 404, "issue_not_found", "Issue not found")

          {:error, :already_running} ->
            error_response(conn, 409, "already_running", "Issue already running")

          {:error, :already_retrying} ->
            error_response(conn, 409, "already_retrying", "Issue already retrying")

          {:error, :not_dispatchable} ->
            error_response(conn, 422, "not_dispatchable", "Issue cannot be dispatched")

          {:error, {:tracker_error, reason}} ->
            error_response(conn, 502, "tracker_error", tracker_error_message(reason))

          {:error, :unavailable} ->
            error_response(conn, 503, "orchestrator_unavailable", "Orchestrator is unavailable")
        end

      :error ->
        error_response(conn, 404, "project_not_found", "Unknown project_id")
    end
  end

  @spec project_issue_update(Conn.t(), map()) :: Conn.t()
  def project_issue_update(conn, %{"project_id" => project_id, "identifier" => identifier})
      when is_binary(project_id) and is_binary(identifier) do
    state_name = extract_issue_state_param(conn)

    if is_binary(state_name) and String.trim(state_name) != "" do
      trimmed = String.trim(state_name)

      case ProjectRegistry.lookup(project_id) do
        {:ok, orch_pid} ->
          case Orchestrator.manual_update_issue(orch_pid, identifier, trimmed) do
            :ok ->
              json(conn, %{updated: true, issue_identifier: identifier, state: trimmed})

            {:error, :not_found} ->
              error_response(conn, 404, "issue_not_found", "Issue not found")

            {:error, {:tracker_error, reason}} ->
              error_response(conn, 502, "tracker_error", tracker_error_message(reason))

            {:error, :unavailable} ->
              error_response(conn, 503, "orchestrator_unavailable", "Orchestrator is unavailable")
          end

        :error ->
          error_response(conn, 404, "project_not_found", "Unknown project_id")
      end
    else
      error_response(conn, 400, "invalid_body", "Expected JSON object with \"state\"")
    end
  end

  @spec project_issue_cancel(Conn.t(), map()) :: Conn.t()
  def project_issue_cancel(conn, %{"project_id" => project_id, "identifier" => identifier})
      when is_binary(project_id) and is_binary(identifier) do
    case ProjectRegistry.lookup(project_id) do
      {:ok, orch_pid} ->
        case Orchestrator.manual_cancel_issue(orch_pid, identifier) do
          :ok ->
            json(conn, %{canceled: true, issue_identifier: identifier})

          {:error, :not_found} ->
            error_response(conn, 404, "issue_not_found", "Issue not active")

          {:error, :unavailable} ->
            error_response(conn, 503, "orchestrator_unavailable", "Orchestrator is unavailable")
        end

      :error ->
        error_response(conn, 404, "project_not_found", "Unknown project_id")
    end
  end

  @spec method_not_allowed(Conn.t(), map()) :: Conn.t()
  def method_not_allowed(conn, _params) do
    error_response(conn, 405, "method_not_allowed", "Method not allowed")
  end

  @spec not_found(Conn.t(), map()) :: Conn.t()
  def not_found(conn, _params) do
    error_response(conn, 404, "not_found", "Route not found")
  end

  defp error_response(conn, status, code, message) do
    conn
    |> put_status(status)
    |> json(%{error: %{code: code, message: message}})
  end

  defp extract_issue_state_param(conn) do
    case conn.body_params do
      %{"state" => name} when is_binary(name) ->
        name

      _ ->
        nil
    end
  end

  defp tracker_error_message(reason) when is_binary(reason), do: reason
  defp tracker_error_message(reason), do: inspect(reason)

  defp orchestrator do
    Endpoint.config(:orchestrator) || ProjectAliases.primary_orchestrator_name()
  end

  defp snapshot_timeout_ms do
    Endpoint.config(:snapshot_timeout_ms) || 15_000
  end
end
