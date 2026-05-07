defmodule SymphonyElixir.Config do
  @moduledoc """
  Runtime configuration loaded from `WORKFLOW.md`.

  Adapter timeouts (`agent.turn_timeout_ms`, `agent.stream_timeout_ms`,
  `agent.read_timeout_ms`, `agent.stall_timeout_ms`) apply to all agent kinds.
  Legacy `codex.*` keys for the same timeouts are still accepted; see
  `SymphonyElixir.Config.Schema`.
  """

  alias SymphonyElixir.Config.Schema
  alias SymphonyElixir.Workflow

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
  def settings do
    case Workflow.current() do
      {:ok, %{config: config}} when is_map(config) ->
        Schema.parse(config)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec settings!() :: Schema.t()
  def settings! do
    case settings() do
      {:ok, settings} ->
        settings

      {:error, reason} ->
        raise ArgumentError, message: format_config_error(reason)
    end
  end

  @spec max_concurrent_agents_for_state(term()) :: pos_integer()
  def max_concurrent_agents_for_state(state_name) when is_binary(state_name) do
    case settings() do
      {:ok, config} ->
        Map.get(
          config.agent.max_concurrent_agents_by_state,
          Schema.normalize_issue_state(state_name),
          config.agent.max_concurrent_agents
        )

      {:error, _reason} ->
        0
    end
  end

  def max_concurrent_agents_for_state(_state_name) do
    case settings() do
      {:ok, config} -> config.agent.max_concurrent_agents
      {:error, _reason} -> 0
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

  @spec workflow_prompt() :: String.t()
  def workflow_prompt do
    case Workflow.current() do
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
        {:ok, config} = SymphonyElixir.ProcessConfig.load()
        config
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
