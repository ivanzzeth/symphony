defmodule SymphonyElixir.Config do
  @moduledoc """
  Runtime configuration loaded from `WORKFLOW.md`.

  Adapter timeouts (`agent.turn_timeout_ms`, `agent.stream_timeout_ms`,
  `agent.read_timeout_ms`, `agent.stall_timeout_ms`) apply to all agent kinds.
  Legacy `codex.*` keys for the same timeouts are still accepted; see
  `SymphonyElixir.Config.Schema`.
  """

  alias SymphonyElixir.Config.Schema
  alias SymphonyElixir.Config.Context
  alias SymphonyElixir.{Workflow, WorkflowStore}

  @default_prompt_template """
  You are working on a Linear issue.

  Identifier: {{ issue.identifier }}
  Title: {{ issue.title }}

  Body:
  {% if issue.description %}
  {{ issue.description }}
  {% else %}
  No description provided.
  {% endif %}
  """

  @type codex_runtime_settings :: %{
          approval_policy: String.t() | map(),
          thread_sandbox: String.t(),
          turn_sandbox_policy: map()
        }

  @spec settings() :: {:ok, Schema.t()} | {:error, term()}
  def settings(opts \\ []) do
    case workflow_loaded(opts) do
      {:ok, %{config: config}} when is_map(config) ->
        Schema.parse(config)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec settings!(keyword()) :: Schema.t()
  def settings!(opts \\ []) do
    case settings(opts) do
      {:ok, settings} ->
        settings

      {:error, reason} ->
        raise ArgumentError, message: format_config_error(reason)
    end
  end

  @doc """
  Settings resolved against the primary per-project workflow store (for dashboard / HTTP UI).
  """
  @spec dashboard_settings() :: {:ok, Schema.t()} | {:error, term()}
  def dashboard_settings do
    settings(workflow_store: WorkflowStore.primary_server())
  end

  @spec dashboard_settings!() :: Schema.t()
  def dashboard_settings! do
    settings!(workflow_store: WorkflowStore.primary_server())
  end

  defp workflow_loaded(opts) do
    store =
      Keyword.get(opts, :workflow_store) ||
        Context.workflow_store() ||
        default_primary_workflow_store()

    case store do
      nil ->
        Workflow.current()

      s ->
        WorkflowStore.current(s)
    end
  end

  defp default_primary_workflow_store do
    case WorkflowStore.whereis() do
      pid when is_pid(pid) -> pid
      _ -> nil
    end
  end

  @spec max_concurrent_agents_for_state(term(), GenServer.server() | nil) :: pos_integer()
  def max_concurrent_agents_for_state(state_name, workflow_store \\ nil) do
    case settings(workflow_store: workflow_store) do
      {:ok, config} ->
        if is_binary(state_name) do
          Map.get(
            config.agent.max_concurrent_agents_by_state,
            Schema.normalize_issue_state(state_name),
            config.agent.max_concurrent_agents
          )
        else
          config.agent.max_concurrent_agents
        end

      {:error, _reason} ->
        0
    end
  end

  @spec codex_turn_sandbox_policy(Path.t() | nil) :: map()
  def codex_turn_sandbox_policy(workspace \\ nil) do
    case Schema.resolve_runtime_turn_sandbox_policy(settings!(), workspace) do
      {:ok, policy} ->
        policy

      {:error, reason} ->
        raise ArgumentError, message: "Invalid codex turn sandbox policy: #{inspect(reason)}"
    end
  end

  @spec workflow_prompt(keyword()) :: String.t()
  def workflow_prompt(opts \\ []) do
    loaded =
      case Keyword.get(opts, :workflow_store) do
        nil ->
          case Context.workflow_store() || default_primary_workflow_store() do
            nil -> Workflow.current()
            store -> WorkflowStore.current(store)
          end

        store ->
          WorkflowStore.current(store)
      end

    case loaded do
      {:ok, %{prompt_template: prompt}} ->
        if String.trim(prompt) == "", do: @default_prompt_template, else: prompt

      _ ->
        @default_prompt_template
    end
  end

  @spec process_config() :: SymphonyElixir.ProcessConfig.t()
  def process_config do
    case Process.whereis(SymphonyElixir.ProcessConfig.Store) do
      pid when is_pid(pid) ->
        SymphonyElixir.ProcessConfig.Store.get()

      _ ->
        case SymphonyElixir.ProcessConfig.load() do
          {:ok, config} ->
            config

          {:error, {:invalid_symphony_yaml, message}} ->
            raise ArgumentError, "Invalid symphony.yaml: #{message}"

          {:error, reason} ->
            raise ArgumentError, "Invalid process config: #{inspect(reason)}"
        end
    end
  end

  @spec server_port() :: non_neg_integer() | nil
  def server_port do
    cli_override = Application.get_env(:symphony_elixir, :server_port_override)

    cond do
      is_integer(cli_override) and cli_override >= 0 -> cli_override
      env_port() -> env_port()
      true -> process_config().server.port
    end
  end

  @spec server_host() :: String.t()
  def server_host do
    cli_override = Application.get_env(:symphony_elixir, :server_host_override)

    cond do
      is_binary(cli_override) and cli_override != "" -> cli_override
      env_host() -> env_host()
      true -> process_config().server.host
    end
  end

  defp env_port do
    case System.get_env("SYMPHONY_PORT") do
      nil -> nil
      "" -> nil
      val -> parse_port(val)
    end
  end

  defp env_host do
    case System.get_env("SYMPHONY_HOST") do
      nil -> nil
      "" -> nil
      val -> val
    end
  end

  defp parse_port(val) do
    case Integer.parse(val) do
      {port, ""} when port >= 0 -> port
      _ -> nil
    end
  end

  @spec observability() :: %{
          dashboard_enabled: boolean(),
          refresh_ms: pos_integer(),
          render_interval_ms: pos_integer()
        }
  def observability do
    process_config().observability
  end

  @spec validate!() :: :ok | {:error, term()}
  def validate! do
    with {:ok, settings} <- settings() do
      validate_semantics(settings)
    end
  end

  @spec validate_orchestrator(GenServer.server() | nil) :: :ok | {:error, term()}
  def validate_orchestrator(workflow_store) do
    opts =
      if is_nil(workflow_store), do: [], else: [workflow_store: workflow_store]

    with {:ok, settings} <- settings(opts) do
      validate_semantics(settings)
    end
  end

  @spec codex_runtime_settings(Path.t() | nil, keyword()) ::
          {:ok, codex_runtime_settings()} | {:error, term()}
  def codex_runtime_settings(workspace \\ nil, opts \\ []) do
    with {:ok, settings} <- settings() do
      with {:ok, turn_sandbox_policy} <-
             Schema.resolve_runtime_turn_sandbox_policy(settings, workspace, opts) do
        {:ok,
         %{
           approval_policy: settings.codex.approval_policy,
           thread_sandbox: settings.codex.thread_sandbox,
           turn_sandbox_policy: turn_sandbox_policy
         }}
      end
    end
  end

  defp validate_semantics(settings) do
    case validate_tracker_kind(settings) do
      :ok -> validate_tracker_requirements(settings)
      error -> error
    end
  end

  defp validate_tracker_kind(%{tracker: %{kind: nil}}), do: {:error, :missing_tracker_kind}

  defp validate_tracker_kind(%{tracker: %{kind: kind}}) when kind not in ["linear", "memory", "github"] do
    {:error, {:unsupported_tracker_kind, kind}}
  end

  defp validate_tracker_kind(_settings), do: :ok

  defp validate_tracker_requirements(%{tracker: %{kind: "linear", api_key: api_key}})
       when not is_binary(api_key) do
    {:error, :missing_linear_api_token}
  end

  defp validate_tracker_requirements(%{tracker: %{kind: "linear", project_slug: project_slug}})
       when not is_binary(project_slug) do
    {:error, :missing_linear_project_slug}
  end

  defp validate_tracker_requirements(%{tracker: %{kind: "github", repo: repo}})
       when not is_binary(repo) do
    {:error, :missing_github_repo}
  end

  defp validate_tracker_requirements(_settings), do: :ok

  defp format_config_error(reason) do
    case reason do
      {:invalid_workflow_config, message} ->
        "Invalid WORKFLOW.md config: #{message}"

      {:missing_workflow_file, path, raw_reason} ->
        "Missing WORKFLOW.md at #{path}: #{inspect(raw_reason)}"

      {:workflow_parse_error, raw_reason} ->
        "Failed to parse WORKFLOW.md: #{inspect(raw_reason)}"

      :workflow_front_matter_not_a_map ->
        "Failed to parse WORKFLOW.md: workflow front matter must decode to a map"

      other ->
        "Invalid WORKFLOW.md config: #{inspect(other)}"
    end
  end
end
