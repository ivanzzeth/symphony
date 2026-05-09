defmodule SymphonyElixirWeb.Presenter do
  @moduledoc """
  Shared projections for the observability API and dashboard.
  """

  alias SymphonyElixir.{CodingAgent, Config, Orchestrator, ProjectSupervisor.Meta, StatusDashboard}

  @spec state_payload(GenServer.name(), timeout()) :: map()
  def state_payload(orchestrator, snapshot_timeout_ms) do
    generated_at = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

    case Orchestrator.snapshot(orchestrator, snapshot_timeout_ms) do
      %{} = snapshot ->
        agent =
          case Map.get(snapshot, :coding_agent) do
            %{kind: kind, label: label} when is_binary(kind) and is_binary(label) ->
              %{kind: kind, kind_label: label}

            %{kind: kind} when is_binary(kind) ->
              %{kind: kind, kind_label: CodingAgent.kind_display_label(kind)}

            _ ->
              agent_kind = Config.dashboard_settings!().agent.kind
              %{kind: agent_kind, kind_label: CodingAgent.kind_display_label(agent_kind)}
          end

        %{
          generated_at: generated_at,
          agent: agent,
          counts: %{
            running: length(snapshot.running),
            retrying: length(snapshot.retrying),
            completed: Map.get(snapshot, :completed, 0)
          },
          running: Enum.map(snapshot.running, &running_entry_payload/1),
          retrying: Enum.map(snapshot.retrying, &retry_entry_payload/1),
          codex_totals: snapshot.codex_totals,
          rate_limits: snapshot.rate_limits
        }

      :timeout ->
        %{generated_at: generated_at, error: %{code: "snapshot_timeout", message: "Snapshot timed out"}}

      :unavailable ->
        %{generated_at: generated_at, error: %{code: "snapshot_unavailable", message: "Snapshot unavailable"}}
    end
  end

  @spec projects_payload(timeout()) :: map()
  def projects_payload(snapshot_timeout_ms) do
    generated_at = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    rows = Meta.list_rows()
    rows = if rows == [], do: fallback_projects_rows(), else: rows

    projects =
      Enum.map(rows, fn row ->
        %{
          project_id: row.project_id,
          status: row.status,
          workflow_path: row.workflow_path,
          counts: project_agent_counts(row.orchestrator_pid, snapshot_timeout_ms)
        }
      end)

    %{generated_at: generated_at, projects: projects}
  end

  defp fallback_projects_rows do
    case Orchestrator.whereis() do
      pid when is_pid(pid) ->
        id = Application.get_env(:symphony_elixir, :primary_project_id) || "default"

        [
          %{
            project_id: id,
            status: :running,
            workflow_path: nil,
            tree_pid: nil,
            orchestrator_pid: pid,
            error_reason: nil,
            updated_at: DateTime.utc_now(:microsecond)
          }
        ]

      _ ->
        []
    end
  end

  defp project_agent_counts(pid, timeout) when is_pid(pid) do
    case Orchestrator.snapshot(pid, timeout) do
      %{} = snap ->
        %{
          running: length(snap.running),
          retrying: length(snap.retrying),
          completed: Map.get(snap, :completed, 0)
        }

      _ ->
        zero_agent_counts()
    end
  end

  defp project_agent_counts(_, _), do: zero_agent_counts()

  defp zero_agent_counts, do: %{running: 0, retrying: 0, completed: 0}

  @spec project_state_payload(String.t(), GenServer.name(), timeout()) :: map()
  def project_state_payload(project_id, orchestrator, snapshot_timeout_ms)
      when is_binary(project_id) do
    state_payload(orchestrator, snapshot_timeout_ms)
    |> Map.put(:project_id, project_id)
  end

  @doc """
  Sums running / retrying / completed counts across per-project dashboard payloads.

  Ignores entries that are not successful state snapshots (missing `:counts`).
  """
  @spec global_agent_totals_from_project_states(%{optional(String.t()) => map()}) :: %{
          running: non_neg_integer(),
          retrying: non_neg_integer(),
          completed: non_neg_integer()
        }
  def global_agent_totals_from_project_states(states) when is_map(states) do
    Enum.reduce(states, %{running: 0, retrying: 0, completed: 0}, fn
      {_id, %{counts: %{running: r, retrying: rt, completed: c}}}, acc
      when is_integer(r) and is_integer(rt) and is_integer(c) ->
        %{
          running: acc.running + r,
          retrying: acc.retrying + rt,
          completed: acc.completed + c
        }

      _, acc ->
        acc
    end)
  end

  @spec issue_payload(String.t(), GenServer.name(), timeout()) :: {:ok, map()} | {:error, :issue_not_found}
  def issue_payload(issue_identifier, orchestrator, snapshot_timeout_ms) when is_binary(issue_identifier) do
    case Orchestrator.snapshot(orchestrator, snapshot_timeout_ms) do
      %{} = snapshot ->
        running = Enum.find(snapshot.running, &(&1.identifier == issue_identifier))
        retry = Enum.find(snapshot.retrying, &(&1.identifier == issue_identifier))

        if is_nil(running) and is_nil(retry) do
          {:error, :issue_not_found}
        else
          {:ok, issue_payload_body(issue_identifier, running, retry)}
        end

      _ ->
        {:error, :issue_not_found}
    end
  end

  @spec refresh_payload(GenServer.name()) :: {:ok, map()} | {:error, :unavailable}
  def refresh_payload(orchestrator) do
    case Orchestrator.request_refresh(orchestrator) do
      :unavailable ->
        {:error, :unavailable}

      payload ->
        {:ok, Map.update!(payload, :requested_at, &DateTime.to_iso8601/1)}
    end
  end

  defp issue_payload_body(issue_identifier, running, retry) do
    %{
      issue_identifier: issue_identifier,
      issue_id: issue_id_from_entries(running, retry),
      status: issue_status(running, retry),
      workspace: %{
        path: workspace_path(issue_identifier, running, retry),
        host: workspace_host(running, retry)
      },
      attempts: %{
        restart_count: restart_count(retry),
        current_retry_attempt: retry_attempt(retry)
      },
      running: running && running_issue_payload(running),
      retry: retry && retry_issue_payload(retry),
      logs: %{
        codex_session_logs: []
      },
      recent_events: (running && recent_events_payload(running)) || [],
      last_error: retry && retry.error,
      tracked: %{}
    }
  end

  defp issue_id_from_entries(running, retry),
    do: (running && running.issue_id) || (retry && retry.issue_id)

  defp restart_count(retry), do: max(retry_attempt(retry) - 1, 0)
  defp retry_attempt(nil), do: 0
  defp retry_attempt(retry), do: retry.attempt || 0

  defp issue_status(_running, nil), do: "running"
  defp issue_status(nil, _retry), do: "retrying"
  defp issue_status(_running, _retry), do: "running"

  defp running_entry_payload(entry) do
    %{
      issue_id: entry.issue_id,
      issue_identifier: entry.identifier,
      state: entry.state,
      worker_host: Map.get(entry, :worker_host),
      workspace_path: Map.get(entry, :workspace_path),
      session_id: entry.session_id,
      turn_count: Map.get(entry, :turn_count, 0),
      last_event: entry.last_codex_event,
      last_message: summarize_message(entry.last_codex_message),
      started_at: iso8601(entry.started_at),
      last_event_at: iso8601(entry.last_codex_timestamp),
      tokens: %{
        input_tokens: entry.codex_input_tokens,
        output_tokens: entry.codex_output_tokens,
        total_tokens: entry.codex_total_tokens
      }
    }
  end

  defp retry_entry_payload(entry) do
    %{
      issue_id: entry.issue_id,
      issue_identifier: entry.identifier,
      attempt: entry.attempt,
      due_at: due_at_iso8601(entry.due_in_ms),
      error: entry.error,
      worker_host: Map.get(entry, :worker_host),
      workspace_path: Map.get(entry, :workspace_path)
    }
  end

  defp running_issue_payload(running) do
    %{
      worker_host: Map.get(running, :worker_host),
      workspace_path: Map.get(running, :workspace_path),
      session_id: running.session_id,
      turn_count: Map.get(running, :turn_count, 0),
      state: running.state,
      started_at: iso8601(running.started_at),
      last_event: running.last_codex_event,
      last_message: summarize_message(running.last_codex_message),
      last_event_at: iso8601(running.last_codex_timestamp),
      tokens: %{
        input_tokens: running.codex_input_tokens,
        output_tokens: running.codex_output_tokens,
        total_tokens: running.codex_total_tokens
      }
    }
  end

  defp retry_issue_payload(retry) do
    %{
      attempt: retry.attempt,
      due_at: due_at_iso8601(retry.due_in_ms),
      error: retry.error,
      worker_host: Map.get(retry, :worker_host),
      workspace_path: Map.get(retry, :workspace_path)
    }
  end

  defp workspace_path(issue_identifier, running, retry) do
    (running && Map.get(running, :workspace_path)) ||
      (retry && Map.get(retry, :workspace_path)) ||
      Path.join(Config.dashboard_settings!().workspace.root, issue_identifier)
  end

  defp workspace_host(running, retry) do
    (running && Map.get(running, :worker_host)) || (retry && Map.get(retry, :worker_host))
  end

  defp recent_events_payload(running) do
    [
      %{
        at: iso8601(running.last_codex_timestamp),
        event: running.last_codex_event,
        message: summarize_message(running.last_codex_message)
      }
    ]
    |> Enum.reject(&is_nil(&1.at))
  end

  defp summarize_message(nil), do: nil
  defp summarize_message(message), do: StatusDashboard.humanize_codex_message(message)

  defp due_at_iso8601(due_in_ms) when is_integer(due_in_ms) do
    DateTime.utc_now()
    |> DateTime.add(div(due_in_ms, 1_000), :second)
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
  end

  defp due_at_iso8601(_due_in_ms), do: nil

  defp iso8601(%DateTime{} = datetime) do
    datetime
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
  end

  defp iso8601(_datetime), do: nil
end
