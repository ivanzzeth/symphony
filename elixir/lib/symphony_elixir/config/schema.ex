defmodule SymphonyElixir.Config.Schema do
  @moduledoc """
  Workflow config schema.

  Adapter-generic timeouts (`turn_timeout_ms`, `stream_timeout_ms`,
  `read_timeout_ms`, `stall_timeout_ms`) live on the `agent` embed. For backward
  compatibility, the same keys may still appear under `codex` in older
  `WORKFLOW.md` files; they are merged into `agent` before validation (with
  `agent` winning when both are set).
  """

  use Ecto.Schema

  import Ecto.Changeset

  require Logger

  alias SymphonyElixir.{PathSafety, Rescue, Workflow}

  @primary_key false

  @type t :: %__MODULE__{}

  defmodule StringOrMap do
    @moduledoc false
    @behaviour Ecto.Type

    @spec type() :: :map
    def type, do: :map

    @spec embed_as(term()) :: :self
    def embed_as(_format), do: :self

    @spec equal?(term(), term()) :: boolean()
    def equal?(left, right), do: left == right

    @spec cast(term()) :: {:ok, String.t() | map()} | :error
    def cast(value) when is_binary(value) or is_map(value), do: {:ok, value}
    def cast(_value), do: :error

    @spec load(term()) :: {:ok, String.t() | map()} | :error
    def load(value) when is_binary(value) or is_map(value), do: {:ok, value}
    def load(_value), do: :error

    @spec dump(term()) :: {:ok, String.t() | map()} | :error
    def dump(value) when is_binary(value) or is_map(value), do: {:ok, value}
    def dump(_value), do: :error
  end

  defmodule Tracker do
    @moduledoc false
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key false

    embedded_schema do
      field(:kind, :string)
      field(:endpoint, :string, default: "https://api.linear.app/graphql")
      field(:api_key, :string)
      field(:project_slug, :string)
      field(:assignee, :string)
      field(:active_states, {:array, :string}, default: ["Todo", "In Progress"])
      field(:terminal_states, {:array, :string}, default: ["Closed", "Cancelled", "Canceled", "Duplicate", "Done"])
      field(:repo, :string)
    end

    @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
    def changeset(schema, attrs) do
      schema
      |> cast(
        attrs,
        [:kind, :endpoint, :api_key, :project_slug, :assignee, :active_states, :terminal_states, :repo],
        empty_values: []
      )
    end
  end

  defmodule Polling do
    @moduledoc false
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key false
    embedded_schema do
      field(:interval_ms, :integer, default: 30_000)
    end

    @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
    def changeset(schema, attrs) do
      schema
      |> cast(attrs, [:interval_ms], empty_values: [])
      |> validate_number(:interval_ms, greater_than: 0)
    end
  end

  defmodule Workspace do
    @moduledoc false
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key false
    embedded_schema do
      field(:root, :string, default: Path.join(System.tmp_dir!(), "symphony_workspaces"))
      field(:base_branch, :string, default: "main")
    end

    @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
    def changeset(schema, attrs) do
      schema
      |> cast(attrs, [:root, :base_branch], empty_values: [])
    end
  end

  defmodule Worker do
    @moduledoc false
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key false
    embedded_schema do
      field(:ssh_hosts, {:array, :string}, default: [])
      field(:max_concurrent_agents_per_host, :integer)
    end

    @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
    def changeset(schema, attrs) do
      schema
      |> cast(attrs, [:ssh_hosts, :max_concurrent_agents_per_host], empty_values: [])
      |> validate_number(:max_concurrent_agents_per_host, greater_than: 0)
    end
  end

  defmodule Agent do
    @moduledoc false
    use Ecto.Schema
    import Ecto.Changeset

    alias SymphonyElixir.Config.Schema

    @primary_key false
    embedded_schema do
      field(:max_concurrent_agents, :integer, default: 10)
      field(:max_turns, :integer, default: 20)
      field(:max_retry_backoff_ms, :integer, default: 300_000)
      field(:max_concurrent_agents_by_state, :map, default: %{})
      field(:kind, :string, default: "codex")
      field(:command, :string)
      field(:turn_timeout_ms, :integer, default: 3_600_000)
      field(:stream_timeout_ms, :integer, default: 120_000)
      field(:read_timeout_ms, :integer, default: 5_000)
      field(:stall_timeout_ms, :integer, default: 300_000)
    end

    @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
    def changeset(schema, attrs) do
      schema
      |> cast(
        attrs,
        [
          :max_concurrent_agents,
          :max_turns,
          :max_retry_backoff_ms,
          :max_concurrent_agents_by_state,
          :kind,
          :command,
          :turn_timeout_ms,
          :stream_timeout_ms,
          :read_timeout_ms,
          :stall_timeout_ms
        ],
        empty_values: []
      )
      |> validate_inclusion(:kind, ["codex", "claude", "cursor"])
      |> validate_number(:max_concurrent_agents, greater_than: 0)
      |> validate_number(:max_turns, greater_than: 0)
      |> validate_number(:max_retry_backoff_ms, greater_than: 0)
      |> validate_number(:turn_timeout_ms, greater_than: 0)
      |> validate_number(:stream_timeout_ms, greater_than: 0)
      |> validate_number(:read_timeout_ms, greater_than: 0)
      |> validate_number(:stall_timeout_ms, greater_than_or_equal_to: 0)
      |> update_change(:max_concurrent_agents_by_state, &Schema.normalize_state_limits/1)
      |> Schema.validate_state_limits(:max_concurrent_agents_by_state)
    end
  end

  defmodule Codex do
    @moduledoc false
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key false
    embedded_schema do
      field(:command, :string)

      field(:approval_policy, StringOrMap,
        default: %{
          "reject" => %{
            "sandbox_approval" => true,
            "rules" => true,
            "mcp_elicitations" => true
          }
        }
      )

      field(:thread_sandbox, :string, default: "workspace-write")
      field(:turn_sandbox_policy, :map)
    end

    @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
    def changeset(schema, attrs) do
      schema
      |> cast(
        attrs,
        [
          :command,
          :approval_policy,
          :thread_sandbox,
          :turn_sandbox_policy
        ],
        empty_values: []
      )
    end
  end

  defmodule Hooks do
    @moduledoc false
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key false
    embedded_schema do
      field(:after_create, :string)
      field(:before_run, :string)
      field(:after_run, :string)
      field(:before_remove, :string)
      field(:timeout_ms, :integer, default: 60_000)
    end

    @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
    def changeset(schema, attrs) do
      schema
      |> cast(attrs, [:after_create, :before_run, :after_run, :before_remove, :timeout_ms], empty_values: [])
      |> validate_number(:timeout_ms, greater_than: 0)
    end
  end

  defmodule Observability do
    @moduledoc false
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key false
    embedded_schema do
      field(:dashboard_enabled, :boolean, default: true)
      field(:refresh_ms, :integer, default: 1_000)
      field(:render_interval_ms, :integer, default: 16)
    end

    @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
    def changeset(schema, attrs) do
      schema
      |> cast(attrs, [:dashboard_enabled, :refresh_ms, :render_interval_ms], empty_values: [])
      |> validate_number(:refresh_ms, greater_than: 0)
      |> validate_number(:render_interval_ms, greater_than: 0)
    end
  end

  defmodule Server do
    @moduledoc false
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key false
    embedded_schema do
      field(:port, :integer)
      field(:host, :string, default: "127.0.0.1")
    end

    @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
    def changeset(schema, attrs) do
      schema
      |> cast(attrs, [:port, :host], empty_values: [])
      |> validate_number(:port, greater_than_or_equal_to: 0)
    end
  end

  defmodule DaemonProject do
    @moduledoc false
    @enforce_keys [:id, :workflow_path, :enabled]
    defstruct @enforce_keys

    @type t :: %__MODULE__{
            id: String.t(),
            workflow_path: String.t(),
            enabled: boolean()
          }
  end

  embedded_schema do
    embeds_one(:tracker, Tracker, on_replace: :update, defaults_to_struct: true)
    embeds_one(:polling, Polling, on_replace: :update, defaults_to_struct: true)
    embeds_one(:workspace, Workspace, on_replace: :update, defaults_to_struct: true)
    embeds_one(:worker, Worker, on_replace: :update, defaults_to_struct: true)
    embeds_one(:agent, Agent, on_replace: :update, defaults_to_struct: true)
    embeds_one(:codex, Codex, on_replace: :update, defaults_to_struct: true)
    embeds_one(:hooks, Hooks, on_replace: :update, defaults_to_struct: true)
    embeds_one(:observability, Observability, on_replace: :update, defaults_to_struct: true)
    embeds_one(:server, Server, on_replace: :update, defaults_to_struct: true)
  end

  @disallowed_workflow_keys ["server", "observability"]

  defp disallowed_workflow_keys do
    @disallowed_workflow_keys ++
      Application.get_env(:symphony_elixir, :extra_disallowed_workflow_keys_for_test, [])
  end

  @legacy_codex_timeout_keys ~w(turn_timeout_ms stream_timeout_ms read_timeout_ms stall_timeout_ms)

  @spec parse(map()) :: {:ok, %__MODULE__{}} | {:error, {:invalid_workflow_config, String.t()}}
  def parse(config) when is_map(config) do
    warn_disallowed_keys(config)

    config
    |> strip_disallowed_keys()
    |> normalize_keys()
    |> merge_legacy_codex_timeouts_into_agent()
    |> drop_nil_values()
    |> changeset()
    |> apply_action(:validate)
    |> case do
      {:ok, settings} ->
        settings = finalize_settings(settings)

        if settings.agent.command not in [nil, ""] do
          {:ok, settings}
        else
          {:error, {:invalid_workflow_config, "agent.command can't be blank"}}
        end

      {:error, changeset} ->
        {:error, {:invalid_workflow_config, format_errors(changeset)}}
    end
  end

  defp warn_disallowed_keys(config) when is_map(config) do
    Enum.each(disallowed_workflow_keys(), fn key ->
      if Map.has_key?(config, key) or Map.has_key?(config, String.to_existing_atom(key)) do
        Logger.warning("[WORKFLOW.md] '#{key}' key is disallowed in WORKFLOW.md. Use symphony.yaml for process-level config.")
      end
    end)
  rescue
    exception ->
      Rescue.log_warning("Config.Schema.warn_disallowed_keys/1 failed, continuing", exception, __STACKTRACE__)
      :ok
  end

  defp strip_disallowed_keys(config) when is_map(config) do
    config
    |> Map.drop(disallowed_workflow_keys())
    |> Map.drop(Enum.map(disallowed_workflow_keys(), &String.to_existing_atom/1))
  rescue
    exception ->
      Rescue.log_warning("Config.Schema.strip_disallowed_keys/1 failed, returning raw config", exception, __STACKTRACE__)
      config
  end

  @spec resolve_turn_sandbox_policy(%__MODULE__{}, Path.t() | nil) :: map()
  def resolve_turn_sandbox_policy(settings, workspace \\ nil) do
    case settings.codex.turn_sandbox_policy do
      %{} = policy ->
        policy

      _ ->
        workspace
        |> default_workspace_root(settings.workspace.root)
        |> expand_local_workspace_root()
        |> default_turn_sandbox_policy()
    end
  end

  @spec resolve_runtime_turn_sandbox_policy(%__MODULE__{}, Path.t() | nil, keyword()) ::
          {:ok, map()} | {:error, term()}
  def resolve_runtime_turn_sandbox_policy(settings, workspace \\ nil, opts \\ []) do
    case settings.codex.turn_sandbox_policy do
      %{} = policy ->
        {:ok, policy}

      _ ->
        workspace
        |> default_workspace_root(settings.workspace.root)
        |> default_runtime_turn_sandbox_policy(opts)
    end
  end

  @spec normalize_issue_state(String.t()) :: String.t()
  def normalize_issue_state(state_name) when is_binary(state_name) do
    String.downcase(state_name)
  end

  @doc false
  @spec normalize_state_limits(nil | map()) :: map()
  def normalize_state_limits(nil), do: %{}

  def normalize_state_limits(limits) when is_map(limits) do
    Enum.reduce(limits, %{}, fn {state_name, limit}, acc ->
      Map.put(acc, normalize_issue_state(to_string(state_name)), limit)
    end)
  end

  @doc false
  @spec validate_state_limits(Ecto.Changeset.t(), atom()) :: Ecto.Changeset.t()
  def validate_state_limits(changeset, field) do
    validate_change(changeset, field, fn ^field, limits ->
      Enum.flat_map(limits, fn {state_name, limit} ->
        cond do
          to_string(state_name) == "" ->
            [{field, "state names must not be blank"}]

          not is_integer(limit) or limit <= 0 ->
            [{field, "limits must be positive integers"}]

          true ->
            []
        end
      end)
    end)
  end

  defp changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [])
    |> cast_embed(:tracker, with: &Tracker.changeset/2)
    |> cast_embed(:polling, with: &Polling.changeset/2)
    |> cast_embed(:workspace, with: &Workspace.changeset/2)
    |> cast_embed(:worker, with: &Worker.changeset/2)
    |> cast_embed(:agent, with: &Agent.changeset/2)
    |> cast_embed(:codex, with: &Codex.changeset/2)
    |> cast_embed(:hooks, with: &Hooks.changeset/2)
    |> cast_embed(:observability, with: &Observability.changeset/2)
    |> cast_embed(:server, with: &Server.changeset/2)
  end

  defp finalize_settings(settings) do
    tracker = %{
      settings.tracker
      | api_key: resolve_secret_setting(settings.tracker.api_key, System.get_env("LINEAR_API_KEY")),
        assignee: resolve_secret_setting(settings.tracker.assignee, System.get_env("LINEAR_ASSIGNEE"))
    }

    workspace = %{
      settings.workspace
      | root: resolve_path_value(settings.workspace.root, Path.join(System.tmp_dir!(), "symphony_workspaces"))
    }

    agent = resolve_agent_command(settings.agent, settings.codex)

    codex = %{
      settings.codex
      | approval_policy: normalize_keys(settings.codex.approval_policy),
        turn_sandbox_policy: normalize_optional_map(settings.codex.turn_sandbox_policy)
    }

    %{settings | tracker: tracker, workspace: workspace, agent: agent, codex: codex}
  end

  defp resolve_agent_command(agent, codex) do
    %{agent | command: agent.command || Map.get(codex, :command) || default_command_for_kind(agent.kind)}
  end

  defp default_command_for_kind("claude"), do: "claude"
  defp default_command_for_kind("cursor"), do: "cursor"
  defp default_command_for_kind("codex"), do: "codex app-server"
  defp default_command_for_kind(_), do: "codex app-server"

  defp normalize_keys(value) when is_map(value) do
    Enum.reduce(value, %{}, fn {key, raw_value}, normalized ->
      Map.put(normalized, normalize_key(key), normalize_keys(raw_value))
    end)
  end

  defp normalize_keys(value) when is_list(value), do: Enum.map(value, &normalize_keys/1)
  defp normalize_keys(value), do: value

  defp normalize_optional_map(nil), do: nil
  defp normalize_optional_map(value) when is_map(value), do: normalize_keys(value)

  defp normalize_key(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_key(value), do: to_string(value)

  # Copies timeout keys from `codex` into `agent` when absent on `agent` (after
  # normalize_keys/1), then removes them from `codex` so only Codex-specific keys remain.
  defp merge_legacy_codex_timeouts_into_agent(config) when is_map(config) do
    codex = Map.get(config, "codex")
    agent = Map.get(config, "agent")
    codex = if is_map(codex), do: codex, else: %{}
    agent = if is_map(agent), do: agent, else: %{}

    legacy_in_codex? =
      Enum.any?(@legacy_codex_timeout_keys, &Map.has_key?(codex, &1))

    if legacy_in_codex? do
      require Logger

      Logger.warning(
        "[WORKFLOW.md] Timeout settings under codex.* (turn_timeout_ms, stream_timeout_ms, read_timeout_ms, stall_timeout_ms) are deprecated; use agent.* instead. Values are still honored for this load. See elixir/README.md."
      )
    end

    {agent_merged, codex_trimmed} =
      Enum.reduce(@legacy_codex_timeout_keys, {agent, codex}, fn key, {a, c} ->
        a2 =
          if Map.has_key?(a, key) do
            a
          else
            case Map.fetch(c, key) do
              {:ok, val} -> Map.put(a, key, val)
              :error -> a
            end
          end

        {a2, Map.delete(c, key)}
      end)

    config
    |> Map.put("agent", agent_merged)
    |> Map.put("codex", codex_trimmed)
  end

  defp drop_nil_values(value) when is_map(value) do
    Enum.reduce(value, %{}, fn {key, nested}, acc ->
      case drop_nil_values(nested) do
        nil -> acc
        normalized -> Map.put(acc, key, normalized)
      end
    end)
  end

  defp drop_nil_values(value) when is_list(value), do: Enum.map(value, &drop_nil_values/1)
  defp drop_nil_values(value), do: value

  defp resolve_secret_setting(nil, fallback), do: normalize_secret_value(fallback)

  defp resolve_secret_setting(value, fallback) when is_binary(value) do
    case resolve_env_value(value, fallback) do
      resolved when is_binary(resolved) -> normalize_secret_value(resolved)
      resolved -> resolved
    end
  end

  defp resolve_path_value(value, default) when is_binary(value) do
    case normalize_path_token(value) do
      :missing ->
        default

      "" ->
        default

      path ->
        path
    end
  end

  defp resolve_env_value(value, fallback) when is_binary(value) do
    case env_reference_name(value) do
      {:ok, env_name} ->
        case System.get_env(env_name) do
          nil -> fallback
          "" -> nil
          env_value -> env_value
        end

      :error ->
        value
    end
  end

  defp normalize_path_token(value) when is_binary(value) do
    case env_reference_name(value) do
      {:ok, env_name} -> resolve_env_token(env_name)
      :error -> value
    end
  end

  defp env_reference_name("$" <> env_name) do
    if String.match?(env_name, ~r/^[A-Za-z_][A-Za-z0-9_]*$/) do
      {:ok, env_name}
    else
      :error
    end
  end

  defp env_reference_name(_value), do: :error

  defp resolve_env_token(env_name) do
    case System.get_env(env_name) do
      nil -> :missing
      env_value -> env_value
    end
  end

  defp normalize_secret_value(value) when is_binary(value) do
    if value == "", do: nil, else: value
  end

  defp normalize_secret_value(_value), do: nil

  defp default_turn_sandbox_policy(workspace) do
    %{
      "type" => "workspaceWrite",
      "writableRoots" => [workspace],
      "readOnlyAccess" => %{"type" => "fullAccess"},
      "networkAccess" => false,
      "excludeTmpdirEnvVar" => false,
      "excludeSlashTmp" => false
    }
  end

  defp default_runtime_turn_sandbox_policy(workspace_root, opts) when is_binary(workspace_root) do
    if Keyword.get(opts, :remote, false) do
      {:ok, default_turn_sandbox_policy(workspace_root)}
    else
      with expanded_workspace_root <- expand_local_workspace_root(workspace_root),
           {:ok, canonical_workspace_root} <- PathSafety.canonicalize(expanded_workspace_root) do
        {:ok, default_turn_sandbox_policy(canonical_workspace_root)}
      end
    end
  end

  defp default_runtime_turn_sandbox_policy(workspace_root, _opts) do
    {:error, {:unsafe_turn_sandbox_policy, {:invalid_workspace_root, workspace_root}}}
  end

  defp default_workspace_root(workspace, _fallback) when is_binary(workspace) and workspace != "",
    do: workspace

  defp default_workspace_root(nil, fallback), do: fallback
  defp default_workspace_root("", fallback), do: fallback
  defp default_workspace_root(workspace, _fallback), do: workspace

  defp expand_local_workspace_root(workspace_root)
       when is_binary(workspace_root) and workspace_root != "" do
    Path.expand(workspace_root)
  end

  defp expand_local_workspace_root(_workspace_root) do
    Path.expand(Path.join(System.tmp_dir!(), "symphony_workspaces"))
  end

  defp format_errors(changeset) do
    changeset
    |> traverse_errors(&translate_error/1)
    |> flatten_errors()
    |> Enum.join(", ")
  end

  defp flatten_errors(errors, prefix \\ nil)

  defp flatten_errors(errors, prefix) when is_map(errors) do
    Enum.flat_map(errors, fn {key, value} ->
      next_prefix =
        case prefix do
          nil -> to_string(key)
          current -> current <> "." <> to_string(key)
        end

      flatten_errors(value, next_prefix)
    end)
  end

  defp flatten_errors(errors, prefix) when is_list(errors) do
    Enum.map(errors, &(prefix <> " " <> &1))
  end

  defp translate_error({message, options}) do
    Enum.reduce(options, message, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", error_value_to_string(value))
    end)
  end

  defp error_value_to_string(value) when is_atom(value), do: Atom.to_string(value)
  defp error_value_to_string(value), do: inspect(value)

  @doc """
  Parses and validates optional `projects` from daemon-level `symphony.yaml`
  (SPEC V1.2 Appendix B.2).

  Each map entry uses the YAML key as `project_id` and expects `workflow` (path
  to `WORKFLOW.md`) and optional `enabled` (default `true`).

  Returns `{:ok, []}` when `projects` is absent or empty. Emits a warning when
  multiple projects resolve to the same workspace root.
  """
  @spec parse_symphony_projects(map(), keyword()) ::
          {:ok, [DaemonProject.t()]} | {:error, String.t()}
  def parse_symphony_projects(yaml_config, opts \\ []) when is_map(yaml_config) do
    base_dir = Keyword.get(opts, :config_base_dir) || File.cwd!()
    projects_raw = Map.get(yaml_config, "projects") || Map.get(yaml_config, :projects)

    cond do
      is_nil(projects_raw) ->
        {:ok, []}

      projects_raw == %{} ->
        {:ok, []}

      not is_map(projects_raw) ->
        {:error, "projects must be a mapping of project_id -> {workflow, enabled}"}

      true ->
        projects_raw
        |> Enum.sort_by(fn {k, _} -> to_string(k) end)
        |> project_rows_from_entries(base_dir)
        |> case do
          {:ok, rows} ->
            warn_workspace_root_collisions(rows)

            {:ok,
             Enum.map(rows, fn row ->
               %DaemonProject{
                 id: row.id,
                 workflow_path: row.workflow_path,
                 enabled: row.enabled
               }
             end)}

          {:error, _} = err ->
            err
        end
    end
  end

  defp project_rows_from_entries(entries, base_dir) do
    Enum.reduce_while(entries, {:ok, []}, fn {raw_id, entry}, {:ok, acc} ->
      project_id = to_string(raw_id)

      cond do
        String.trim(project_id) == "" ->
          {:halt, {:error, "projects contains an empty project_id key"}}

        not is_map(entry) ->
          {:halt, {:error, "project #{inspect(project_id)}: entry must be a mapping with workflow (and optional enabled)"}}

        true ->
          workflow_rel = Map.get(entry, "workflow") || Map.get(entry, :workflow)

          if not is_binary(workflow_rel) or String.trim(workflow_rel) == "" do
            {:halt, {:error, "project #{project_id}: workflow must be a non-empty string path"}}
          else
            case parse_symphony_project_enabled(entry, project_id) do
              {:error, msg} ->
                {:halt, {:error, msg}}

              {:ok, enabled} ->
                workflow_abs = Path.expand(String.trim(workflow_rel), base_dir)

                cond do
                  not File.regular?(workflow_abs) ->
                    {:halt, {:error, "project #{project_id}: workflow file not found at #{workflow_abs}"}}

                  true ->
                    case Workflow.load(workflow_abs) do
                      {:ok, %{config: wf_config}} ->
                        workflow_dir = Path.dirname(workflow_abs)
                        root = resolve_collision_workspace_root(wf_config, workflow_dir)

                        canon =
                          case PathSafety.canonicalize(root) do
                            {:ok, c} -> c
                            {:error, _} -> root
                          end

                        row = %{
                          id: project_id,
                          workflow_path: workflow_abs,
                          enabled: enabled,
                          canonical_workspace_root: canon
                        }

                        {:cont, {:ok, [row | acc]}}

                      {:error, reason} ->
                        {:halt, {:error, "project #{project_id}: #{format_workflow_load_error(reason)}"}}
                    end
                end
            end
          end
      end
    end)
    |> case do
      {:ok, rows} -> {:ok, Enum.reverse(rows)}
      {:error, _} = err -> err
    end
  end

  defp parse_symphony_project_enabled(entry, project_id) do
    key_result =
      case Map.fetch(entry, "enabled") do
        {:ok, val} -> {:ok, val}
        :error -> Map.fetch(entry, :enabled)
      end

    case key_result do
      :error ->
        {:ok, true}

      {:ok, val} ->
        case val do
          true -> {:ok, true}
          false -> {:ok, false}
          other -> {:error, "project #{project_id}: enabled must be a boolean, got: #{inspect(other)}"}
        end
    end
  end

  defp resolve_collision_workspace_root(wf_config, workflow_dir) do
    ws = Map.get(wf_config, "workspace") || Map.get(wf_config, :workspace) || %{}
    root = Map.get(ws, "root") || Map.get(ws, :root)

    default_root = Path.join(System.tmp_dir!(), "symphony_workspaces")

    cond do
      is_binary(root) and String.trim(root) != "" ->
        Path.expand(String.trim(root), workflow_dir)

      true ->
        Path.expand(default_root)
    end
  end

  defp format_workflow_load_error({:missing_workflow_file, path, reason}) do
    "failed to read workflow #{path}: #{inspect(reason)}"
  end

  defp format_workflow_load_error(:workflow_front_matter_not_a_map) do
    "workflow front matter must decode to a YAML mapping"
  end

  defp format_workflow_load_error({:workflow_parse_error, reason}) do
    "failed to parse workflow YAML front matter: #{inspect(reason)}"
  end

  defp format_workflow_load_error(other) do
    "failed to load workflow: #{inspect(other)}"
  end

  defp warn_workspace_root_collisions(rows) do
    rows
    |> Enum.group_by(& &1.canonical_workspace_root)
    |> Enum.each(fn {root, group} ->
      if length(group) > 1 do
        ids = group |> Enum.map(& &1.id) |> Enum.sort() |> Enum.join(", ")

        Logger.warning("[symphony.yaml] workspace.root collision: multiple projects share root #{inspect(root)} (#{ids})")
      end
    end)
  end
end
