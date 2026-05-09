defmodule SymphonyElixirWeb.DashboardLive do
  @moduledoc """
  Live observability dashboard for Symphony.
  """

  use Phoenix.LiveView, layout: {SymphonyElixirWeb.Layouts, :app}

  alias SymphonyElixir.{CodingAgent, Config, ProjectRegistry}
  alias SymphonyElixir.ProjectAliases
  alias SymphonyElixir.ProjectSupervisor.Meta
  alias SymphonyElixir.ProcessConfig
  alias SymphonyElixirWeb.{Endpoint, ObservabilityPubSub, Presenter}

  @runtime_tick_ms 1_000

  @impl true
  def mount(_params, _session, socket) do
    rows = Meta.list_rows()
    multi? = multi_project_dashboard?(rows)

    socket =
      socket
      |> assign(:multi_project, multi?)
      |> assign(:project_states, %{})
      |> assign(:global_totals, %{running: 0, retrying: 0, completed: 0})
      |> assign(:projects_meta, if(multi?, do: rows, else: []))
      |> assign(:selected_project_id, if(multi?, do: default_selected_project_id(rows), else: nil))
      |> assign(:now, DateTime.utc_now())
      |> then(fn s ->
        if multi? do
          assign(s, :payload, %{pending: true})
        else
          assign(s, :payload, load_payload())
        end
      end)

    if connected?(socket) do
      :ok = ObservabilityPubSub.subscribe()
      schedule_runtime_tick()

      if multi? do
        request_project_snapshots_async(socket)
      end
    end

    {:ok, socket}
  end

  @impl true
  def handle_event("select_project", %{"id" => project_id}, socket) do
    if socket.assigns.multi_project do
      payload =
        case Map.fetch(socket.assigns.project_states, project_id) do
          {:ok, p} -> p
          :error -> %{pending: true}
        end

      {:noreply,
       socket
       |> assign(:selected_project_id, project_id)
       |> assign(:payload, payload)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info(:runtime_tick, socket) do
    schedule_runtime_tick()

    {:noreply,
     socket
     |> assign(:now, DateTime.utc_now())
     |> maybe_refresh_coding_agent()}
  end

  @impl true
  def handle_info(:observability_updated, socket) do
    if socket.assigns.multi_project do
      request_project_snapshots_async(socket)

      {:noreply,
       socket
       |> assign(:now, DateTime.utc_now())}
    else
      {:noreply,
       socket
       |> assign(:payload, load_payload())
       |> assign(:now, DateTime.utc_now())}
    end
  end

  @impl true
  def handle_info({:dashboard_project_state, project_id, payload}, socket) do
    if socket.assigns.multi_project do
      states = Map.put(socket.assigns.project_states, project_id, payload)
      totals = Presenter.global_agent_totals_from_project_states(states)

      socket =
        socket
        |> assign(:project_states, states)
        |> assign(:global_totals, totals)

      socket =
        if project_id == socket.assigns.selected_project_id do
          assign(socket, :payload, payload)
        else
          socket
        end

      schedule_project_poll(project_id, project_poll_interval_ms(project_id))

      {:noreply, maybe_refresh_coding_agent(socket)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:poll_project, project_id}, socket) do
    if socket.assigns.multi_project do
      spawn_project_state_fetch(project_id)
      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section class="dashboard-shell">
      <%= if @multi_project do %>
        <nav class="project-tab-bar" aria-label="Projects">
          <div class="project-tabs">
            <button
              :for={row <- @projects_meta}
              type="button"
              class={project_tab_button_class(row.project_id == @selected_project_id)}
              phx-click="select_project"
              phx-value-id={row.project_id}
            >
              <span class="project-tab-label"><%= row.project_id %></span>
              <span class={project_meta_badge_class(row.status)}>
                <%= project_meta_status_label(row.status) %>
              </span>
              <span class="project-tab-counts mono">
                <%= project_tab_counts_preview(@project_states[row.project_id]) %>
              </span>
            </button>
          </div>
        </nav>

        <section class="global-summary-card" aria-label="Global agent totals">
          <div class="global-summary-grid">
            <div>
              <p class="global-summary-eyebrow">All projects</p>
              <p class="global-summary-title">Agent totals</p>
            </div>
            <div class="global-summary-metrics">
              <span class="global-summary-metric">
                Running <strong class="numeric"><%= @global_totals.running %></strong>
              </span>
              <span class="global-summary-metric">
                Retrying <strong class="numeric"><%= @global_totals.retrying %></strong>
              </span>
              <span class="global-summary-metric">
                Completed <strong class="numeric"><%= @global_totals.completed %></strong>
              </span>
            </div>
          </div>
        </section>
      <% end %>

      <header class="hero-card">
        <div class="hero-grid">
          <div>
            <p class="eyebrow">
              Symphony Observability
            </p>
            <h1 class="hero-title">
              Operations Dashboard
            </h1>
            <p class="hero-copy">
              Current state, retry pressure, token usage, and orchestration health for the active Symphony runtime.
            </p>
          </div>

          <div class="status-stack">
            <span class="status-badge status-badge-live">
              <span class="status-badge-dot"></span>
              Live
            </span>
            <span class="status-badge status-badge-offline">
              <span class="status-badge-dot"></span>
              Offline
            </span>
          </div>
        </div>
      </header>

      <%= if Map.get(@payload, :pending) do %>
        <section class="section-card">
          <p class="empty-state">Loading project snapshot…</p>
        </section>
      <% else %>
        <%= if @payload[:error] do %>
          <section class="error-card">
            <h2 class="error-title">
              Snapshot unavailable
            </h2>
            <p class="error-copy">
              <strong><%= @payload.error.code %>:</strong> <%= @payload.error.message %>
            </p>
          </section>
        <% else %>
          <section class="metric-grid">
            <article class="metric-card">
              <p class="metric-label">Coding agent</p>
              <p class="metric-value"><%= @payload.agent.kind_label %></p>
              <p class="metric-detail">
                Active <span class="mono">agent.kind</span>:
                <span class="mono"><%= @payload.agent.kind %></span>
              </p>
            </article>

            <article class="metric-card">
              <p class="metric-label">Running</p>
              <p class="metric-value numeric"><%= @payload.counts.running %></p>
              <p class="metric-detail">Active issue sessions in the current runtime.</p>
            </article>

            <article class="metric-card">
              <p class="metric-label">Retrying</p>
              <p class="metric-value numeric"><%= @payload.counts.retrying %></p>
              <p class="metric-detail">Issues waiting for the next retry window.</p>
            </article>

            <article class="metric-card">
              <p class="metric-label">Total tokens</p>
              <p class="metric-value numeric"><%= format_int(@payload.codex_totals.total_tokens) %></p>
              <p class="metric-detail numeric">
                In <%= format_int(@payload.codex_totals.input_tokens) %> / Out <%= format_int(@payload.codex_totals.output_tokens) %>
              </p>
            </article>

            <article class="metric-card">
              <p class="metric-label">Runtime</p>
              <p class="metric-value numeric"><%= format_runtime_seconds(total_runtime_seconds(@payload, @now)) %></p>
              <p class="metric-detail">Total Codex runtime across completed and active sessions.</p>
            </article>
          </section>

          <section class="section-card">
            <div class="section-header">
              <div>
                <h2 class="section-title">Rate limits</h2>
                <p class="section-copy">Latest upstream rate-limit snapshot, when available.</p>
              </div>
            </div>

            <pre class="code-panel"><%= pretty_value(@payload.rate_limits) %></pre>
          </section>

          <section class="section-card">
            <div class="section-header">
              <div>
                <h2 class="section-title">Running sessions</h2>
                <p class="section-copy">Active issues, last known agent activity, and token usage.</p>
              </div>
            </div>

            <%= if @payload.running == [] do %>
              <p class="empty-state">No active sessions.</p>
            <% else %>
              <div class="table-wrap">
                <table class="data-table data-table-running">
                  <colgroup>
                    <col style="width: 12rem;" />
                    <col style="width: 8rem;" />
                    <col style="width: 7.5rem;" />
                    <col style="width: 8.5rem;" />
                    <col />
                    <col style="width: 10rem;" />
                  </colgroup>
                  <thead>
                    <tr>
                      <th>Issue</th>
                      <th>State</th>
                      <th>Session</th>
                      <th>Runtime / turns</th>
                      <th>Codex update</th>
                      <th>Tokens</th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr :for={entry <- @payload.running}>
                      <td>
                        <div class="issue-stack">
                          <span class="issue-id"><%= entry.issue_identifier %></span>
                          <a class="issue-link" href={"/api/v1/#{entry.issue_identifier}"}>JSON details</a>
                        </div>
                      </td>
                      <td>
                        <span class={state_badge_class(entry.state)}>
                          <%= entry.state %>
                        </span>
                      </td>
                      <td>
                        <div class="session-stack">
                          <%= if entry.session_id do %>
                            <button
                              type="button"
                              class="subtle-button"
                              data-label="Copy ID"
                              data-copy={entry.session_id}
                              onclick="navigator.clipboard.writeText(this.dataset.copy); this.textContent = 'Copied'; clearTimeout(this._copyTimer); this._copyTimer = setTimeout(() => { this.textContent = this.dataset.label }, 1200);"
                            >
                              Copy ID
                            </button>
                          <% else %>
                            <span class="muted">n/a</span>
                          <% end %>
                        </div>
                      </td>
                      <td class="numeric"><%= format_runtime_and_turns(entry.started_at, entry.turn_count, @now) %></td>
                      <td>
                        <div class="detail-stack">
                          <span
                            class="event-text"
                            title={entry.last_message || to_string(entry.last_event || "n/a")}
                          ><%= entry.last_message || to_string(entry.last_event || "n/a") %></span>
                          <span class="muted event-meta">
                            <%= entry.last_event || "n/a" %>
                            <%= if entry.last_event_at do %>
                              · <span class="mono numeric"><%= entry.last_event_at %></span>
                            <% end %>
                          </span>
                        </div>
                      </td>
                      <td>
                        <div class="token-stack numeric">
                          <span>Total: <%= format_int(entry.tokens.total_tokens) %></span>
                          <span class="muted">In <%= format_int(entry.tokens.input_tokens) %> / Out <%= format_int(entry.tokens.output_tokens) %></span>
                        </div>
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
            <% end %>
          </section>

          <section class="section-card">
            <div class="section-header">
              <div>
                <h2 class="section-title">Retry queue</h2>
                <p class="section-copy">Issues waiting for the next retry window.</p>
              </div>
            </div>

            <%= if @payload.retrying == [] do %>
              <p class="empty-state">No issues are currently backing off.</p>
            <% else %>
              <div class="table-wrap">
                <table class="data-table" style="min-width: 680px;">
                  <thead>
                    <tr>
                      <th>Issue</th>
                      <th>Attempt</th>
                      <th>Due at</th>
                      <th>Error</th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr :for={entry <- @payload.retrying}>
                      <td>
                        <div class="issue-stack">
                          <span class="issue-id"><%= entry.issue_identifier %></span>
                          <a class="issue-link" href={"/api/v1/#{entry.issue_identifier}"}>JSON details</a>
                        </div>
                      </td>
                      <td><%= entry.attempt %></td>
                      <td class="mono"><%= entry.due_at || "n/a" %></td>
                      <td><%= entry.error || "n/a" %></td>
                    </tr>
                  </tbody>
                </table>
              </div>
            <% end %>
          </section>
        <% end %>
      <% end %>
    </section>
    """
  end

  defp multi_project_dashboard?(rows) when is_list(rows), do: length(rows) > 1

  defp default_selected_project_id([]), do: "default"

  defp default_selected_project_id(rows) do
    rows
    |> Enum.find(fn row -> row.status == :running and is_pid(row.orchestrator_pid) end)
    |> case do
      %{project_id: id} -> id
      _ -> List.first(rows).project_id
    end
  end

  defp request_project_snapshots_async(socket) do
    Enum.each(socket.assigns.projects_meta, fn row ->
      spawn_project_state_fetch(row.project_id)
    end)
  end

  defp spawn_project_state_fetch(project_id) when is_binary(project_id) do
    parent = self()
    timeout = snapshot_timeout_ms()

    Task.start(fn ->
      payload =
        case ProjectRegistry.lookup(project_id) do
          {:ok, orch} ->
            Presenter.project_state_payload(project_id, orch, timeout)

          :error ->
            %{
              generated_at: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
              error: %{
                code: "project_unavailable",
                message: "No orchestrator registered for this project yet."
              }
            }
        end

      send(parent, {:dashboard_project_state, project_id, payload})
    end)
  end

  defp schedule_project_poll(project_id, ms) when is_binary(project_id) and is_integer(ms) do
    ms = max(ms, 250)
    Process.send_after(self(), {:poll_project, project_id}, ms)
  end

  defp project_poll_interval_ms(project_id) when is_binary(project_id) do
    store = workflow_store_pid_for(project_id)

    case store do
      pid when is_pid(pid) ->
        case Config.settings(workflow_store: pid) do
          {:ok, %{observability: %{refresh_ms: ms}}} when is_integer(ms) and ms > 0 ->
            ms

          _ ->
            daemon_refresh_fallback_ms()
        end

      _ ->
        daemon_refresh_fallback_ms()
    end
  end

  defp daemon_refresh_fallback_ms do
    case ProcessConfig.load() do
      {:ok, %{observability: %{refresh_ms: ms}}} when is_integer(ms) and ms > 0 -> ms
      _ -> 1_000
    end
  end

  defp workflow_store_pid_for(project_id) when is_binary(project_id) do
    case Registry.lookup(SymphonyElixir.ProjectProcessRegistry, {project_id, :workflow_store}) do
      [{pid, _}] when is_pid(pid) ->
        if Process.alive?(pid), do: pid, else: nil

      [] ->
        nil
    end
  end

  defp project_tab_button_class(true), do: "project-tab project-tab-active"
  defp project_tab_button_class(false), do: "project-tab"

  defp project_meta_badge_class(:running), do: "project-meta-badge project-meta-badge-running"
  defp project_meta_badge_class(:starting), do: "project-meta-badge project-meta-badge-starting"
  defp project_meta_badge_class(:error), do: "project-meta-badge project-meta-badge-error"
  defp project_meta_badge_class(:stopped), do: "project-meta-badge project-meta-badge-stopped"
  defp project_meta_badge_class(_), do: "project-meta-badge"

  defp project_meta_status_label(:running), do: "Running"
  defp project_meta_status_label(:starting), do: "Starting"
  defp project_meta_status_label(:error), do: "Error"
  defp project_meta_status_label(:stopped), do: "Stopped"
  defp project_meta_status_label(other), do: to_string(other)

  defp project_tab_counts_preview(nil), do: "…"

  defp project_tab_counts_preview(%{error: _}), do: "—"

  defp project_tab_counts_preview(%{counts: %{running: r, retrying: rt, completed: c}}) do
    "run #{r} · retry #{rt} · done #{c}"
  end

  defp project_tab_counts_preview(_), do: "…"

  defp load_payload do
    Presenter.state_payload(orchestrator(), snapshot_timeout_ms())
  end

  defp maybe_refresh_coding_agent(socket) do
    if socket.assigns.multi_project do
      maybe_refresh_coding_agent_multi(socket)
    else
      maybe_refresh_coding_agent_single(socket)
    end
  end

  defp maybe_refresh_coding_agent_single(socket) do
    payload = socket.assigns.payload

    cond do
      match?(%{error: _}, payload) ->
        socket

      true ->
        case Config.dashboard_settings() do
          {:ok, config} ->
            apply_agent_label_override(socket, config.agent.kind, CodingAgent.kind_display_label(config.agent.kind))

          {:error, _} ->
            socket
        end
    end
  end

  defp maybe_refresh_coding_agent_multi(socket) do
    payload = socket.assigns.payload
    project_id = socket.assigns.selected_project_id

    cond do
      Map.get(payload, :pending) == true ->
        socket

      match?(%{error: _}, payload) ->
        socket

      not is_binary(project_id) ->
        socket

      true ->
        case workflow_store_pid_for(project_id) do
          pid when is_pid(pid) ->
            case Config.settings(workflow_store: pid) do
              {:ok, config} ->
                apply_agent_label_override(
                  socket,
                  config.agent.kind,
                  CodingAgent.kind_display_label(config.agent.kind)
                )

              {:error, _} ->
                socket
            end

          _ ->
            maybe_refresh_coding_agent_single(socket)
        end
    end
  end

  defp apply_agent_label_override(socket, kind, label) do
    payload = socket.assigns.payload

    case Map.get(payload, :agent) do
      %{kind: ^kind, kind_label: ^label} ->
        socket

      _ ->
        assign(socket, :payload, Map.put(payload, :agent, %{kind: kind, kind_label: label}))
    end
  end

  defp orchestrator do
    Endpoint.config(:orchestrator) || ProjectAliases.primary_orchestrator_name()
  end

  defp snapshot_timeout_ms do
    Endpoint.config(:snapshot_timeout_ms) || 15_000
  end

  defp completed_runtime_seconds(payload) do
    (payload.codex_totals && payload.codex_totals.seconds_running) || 0
  end

  defp total_runtime_seconds(payload, now) do
    completed_runtime_seconds(payload) +
      Enum.reduce(payload.running, 0, fn entry, total ->
        total + runtime_seconds_from_started_at(entry.started_at, now)
      end)
  end

  defp format_runtime_and_turns(started_at, turn_count, now) when is_integer(turn_count) and turn_count > 0 do
    "#{format_runtime_seconds(runtime_seconds_from_started_at(started_at, now))} / #{turn_count}"
  end

  defp format_runtime_and_turns(started_at, _turn_count, now),
    do: format_runtime_seconds(runtime_seconds_from_started_at(started_at, now))

  defp format_runtime_seconds(seconds) when is_number(seconds) do
    whole_seconds = max(trunc(seconds), 0)
    mins = div(whole_seconds, 60)
    secs = rem(whole_seconds, 60)
    "#{mins}m #{secs}s"
  end

  defp runtime_seconds_from_started_at(%DateTime{} = started_at, %DateTime{} = now) do
    DateTime.diff(now, started_at, :second)
  end

  defp runtime_seconds_from_started_at(started_at, %DateTime{} = now) when is_binary(started_at) do
    case DateTime.from_iso8601(started_at) do
      {:ok, parsed, _offset} -> runtime_seconds_from_started_at(parsed, now)
      _ -> 0
    end
  end

  defp runtime_seconds_from_started_at(_started_at, _now), do: 0

  defp format_int(value) when is_integer(value) do
    value
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/.{3}(?=.)/, "\\0,")
    |> String.reverse()
  end

  defp format_int(_value), do: "n/a"

  defp state_badge_class(state) do
    base = "state-badge"
    normalized = state |> to_string() |> String.downcase()

    cond do
      String.contains?(normalized, ["progress", "running", "active"]) -> "#{base} state-badge-active"
      String.contains?(normalized, ["blocked", "error", "failed"]) -> "#{base} state-badge-danger"
      String.contains?(normalized, ["todo", "queued", "pending", "retry"]) -> "#{base} state-badge-warning"
      true -> base
    end
  end

  defp schedule_runtime_tick do
    Process.send_after(self(), :runtime_tick, @runtime_tick_ms)
  end

  defp pretty_value(nil), do: "n/a"
  defp pretty_value(value), do: inspect(value, pretty: true, limit: :infinity)
end
