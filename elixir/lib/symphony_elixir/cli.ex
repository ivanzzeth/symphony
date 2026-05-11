defmodule SymphonyElixir.CLI do
  @moduledoc """
  Escript entrypoint for running Symphony with an explicit WORKFLOW.md path.
  """

  alias SymphonyElixir.LogFile
  alias SymphonyElixir.ProcessConfig

  @acknowledgement_switch :i_understand_that_this_will_be_running_without_the_usual_guardrails
  @switches [
    {@acknowledgement_switch, :boolean},
    logs_root: :string,
    port: :integer,
    host: :string,
    config: :string
  ]

  @type ensure_started_result :: {:ok, [atom()]} | {:error, term()}
  @type deps :: %{
          file_regular?: (String.t() -> boolean()),
          set_workflow_file_path: (String.t() -> :ok | {:error, term()}),
          set_logs_root: (String.t() -> :ok | {:error, term()}),
          set_server_port_override: (non_neg_integer() | nil -> :ok | {:error, term()}),
          set_server_host_override: (String.t() | nil -> :ok | {:error, term()}),
          set_config_arg: (String.t() | nil -> :ok | {:error, term()}),
          ensure_all_started: (-> ensure_started_result())
        }

  @spec main([String.t()]) :: no_return()
  def main(args) do
    if help_requested?(args) do
      IO.puts(help_text(args))
      System.halt(0)
    end

    case parse_init_command(args) do
      {:init, init_opts} ->
        case SymphonyElixir.Init.run(init_opts) do
          :ok ->
            System.halt(0)

          {:error, message} ->
            IO.puts(:stderr, message)
            System.halt(1)
        end

      {:not_init, rest} ->
        evaluate_and_wait(rest)
    end
  end

  @doc false
  @spec parse_init_command([String.t()]) :: {:init, keyword()} | {:not_init, [String.t()]}
  def parse_init_command(args) do
    case args do
      ["init" | rest] ->
        {parsed, _, _} =
          OptionParser.parse(rest,
            strict: [target_dir: :string, upgrade: :boolean, force: :boolean]
          )

        target = Keyword.get(parsed, :target_dir, File.cwd!()) |> Path.expand()
        upgrade? = Keyword.get(parsed, :upgrade, false)
        force? = Keyword.get(parsed, :force, false)
        {:init, [target_dir: target, upgrade: upgrade?, force: force?]}

      _ ->
        {:not_init, args}
    end
  end

  defp evaluate_and_wait(args) do
    case evaluate(args) do
      :ok ->
        wait_for_shutdown()

      {:error, message} ->
        IO.puts(:stderr, message)
        System.halt(1)
    end
  end

  @doc false
  @spec extract_project_pairs([String.t()]) ::
          {:ok, [{String.t(), String.t()}], [String.t()]} | {:error, String.t()}
  def extract_project_pairs(argv) when is_list(argv) do
    walk_extract_projects(argv, [], [])
  end

  defp walk_extract_projects(["--project"], _, _) do
    {:error, "--project requires <project-id>.<field> and <value> (example: --project service-a.workflow /path/to/W.md)"}
  end

  defp walk_extract_projects(["--project", _], _, _) do
    {:error, "--project requires <project-id>.<field> and <value> (example: --project service-a.workflow /path/to/W.md)"}
  end

  defp walk_extract_projects(["--project", dot_path, raw_value | rest], pairs, argv_acc) do
    walk_extract_projects(rest, [{dot_path, raw_value} | pairs], argv_acc)
  end

  defp walk_extract_projects([token | rest], pairs, argv_acc) do
    walk_extract_projects(rest, pairs, [token | argv_acc])
  end

  defp walk_extract_projects([], pairs, argv_acc) do
    {:ok, Enum.reverse(pairs), Enum.reverse(argv_acc)}
  end

  defp help_requested?(args) do
    Enum.any?(args, &(&1 == "--help" or &1 == "-h"))
  end

  @spec help_text([String.t()]) :: String.t()
  def help_text(args \\ []) do
    preview =
      case extract_config_path_from_argv(args) do
        nil ->
          case extract_project_pairs(args) do
            {:ok, pairs, _} when pairs != [] ->
              "\nHint: pass --config <symphony.yaml> to preview merged `projects` in this help output.\n"

            _ ->
              ""
          end

        config_path ->
          case extract_project_pairs(args) do
            {:error, msg} ->
              "\n#{msg}\n"

            {:ok, pairs, _} ->
              prev_o = Application.fetch_env(:symphony_elixir, :symphony_project_overrides)
              prev_c = Application.fetch_env(:symphony_elixir, :config_arg)

              try do
                if pairs != [] do
                  Application.put_env(:symphony_elixir, :symphony_project_overrides, pairs)
                else
                  Application.delete_env(:symphony_elixir, :symphony_project_overrides)
                end

                Application.put_env(:symphony_elixir, :config_arg, config_path)

                body =
                  case ProcessConfig.load(config_path, skip_overrides: true) do
                    {:ok, pc} ->
                      case pc.projects do
                        [] ->
                          "  (no projects in effective config)\n"

                        projects ->
                          (projects
                           |> Enum.sort_by(& &1.id)
                           |> Enum.map_join("\n", fn p ->
                             "  #{p.id}  workflow=#{p.workflow_path}  enabled=#{p.enabled}"
                           end)) <> "\n"
                      end

                    {:error, {:invalid_symphony_yaml, msg}} ->
                      "  Error: #{msg}\n"

                    {:error, other} ->
                      "  Error: #{inspect(other)}\n"
                  end

                "\nEffective projects for #{config_path}:\n" <> body
              after
                restore_env_snapshot(:symphony_project_overrides, prev_o)
                restore_env_snapshot(:config_arg, prev_c)
              end
          end
      end

    usage_message() <> "\n\n" <> multi_project_help_section() <> preview
  end

  defp restore_env_snapshot(key, {:ok, val}), do: Application.put_env(:symphony_elixir, key, val)
  defp restore_env_snapshot(key, :error), do: Application.delete_env(:symphony_elixir, key)

  defp extract_config_path_from_argv(argv) do
    walk_config_path(argv, nil)
  end

  defp walk_config_path(["--config", path | rest], _) do
    trimmed = String.trim(path)

    next =
      if trimmed == "" do
        nil
      else
        Path.expand(trimmed)
      end

    walk_config_path(rest, next)
  end

  defp walk_config_path([_ | rest], acc), do: walk_config_path(rest, acc)
  defp walk_config_path([], acc), do: acc

  defp multi_project_help_section do
    """
    Multi-project (SPEC V1.2): with no positional WORKFLOW.md, if symphony.yaml
    contains a top-level `projects` key, Symphony starts in multi-project mode
    using the first enabled project workflow. A positional WORKFLOW.md selects
    legacy single-project mode.

      --project <project-id>.<field> <value>

    Repeat `--project` to override `workflow` (path string) or `enabled` (true
    or false) for a project entry before config is validated.

    """
  end

  @spec evaluate([String.t()], deps()) :: :ok | {:error, String.t()}
  def evaluate(args, deps \\ runtime_deps()) do
    case extract_project_pairs(args) do
      {:error, message} ->
        {:error, message}

      {:ok, project_pairs, argv} ->
        :ok = persist_project_overrides(project_pairs)

        try do
          case OptionParser.parse(argv, strict: @switches) do
            {opts, positional, []} when length(positional) <= 1 ->
              run_parsed(opts, positional, deps)

            _ ->
              {:error, usage_message()}
          end
        after
          Application.delete_env(:symphony_elixir, :symphony_project_overrides)
        end
    end
  end

  defp persist_project_overrides([]) do
    Application.delete_env(:symphony_elixir, :symphony_project_overrides)
    :ok
  end

  defp persist_project_overrides(pairs) do
    Application.put_env(:symphony_elixir, :symphony_project_overrides, pairs)
    :ok
  end

  defp run_parsed(opts, positional, deps) do
    with :ok <- require_guardrails_acknowledgement(opts),
         :ok <- maybe_set_logs_root(opts, deps),
         :ok <- maybe_set_config_arg(opts, deps),
         :ok <- maybe_set_server_port(opts, deps),
         :ok <- maybe_set_server_host(opts, deps),
         :ok <- resolve_and_run_workflow(positional, deps) do
      :ok
    end
  end

  defp resolve_and_run_workflow([], deps) do
    cli_cfg = Application.get_env(:symphony_elixir, :config_arg)
    path = ProcessConfig.config_path(cli_cfg)
    raw = ProcessConfig.load_yaml_config(path)
    overrides = Application.get_env(:symphony_elixir, :symphony_project_overrides) || []

    case ProcessConfig.apply_symphony_project_cli_overrides(raw, overrides) do
      {:error, message} ->
        {:error, "CLI --project: #{message}"}

      {:ok, merged_yaml} ->
        if has_top_level_projects_key?(merged_yaml) do
          case ProcessConfig.load(cli_cfg, skip_overrides: true) do
            {:ok, pc} ->
              case Enum.find(Enum.sort_by(pc.projects, & &1.id), & &1.enabled) do
                nil ->
                  {:error,
                   "symphony.yaml multi-project mode requires at least one enabled project " <>
                     "(after CLI --project overrides)."}

                %{workflow_path: wf} ->
                  run(wf, deps)
              end

            {:error, {:invalid_symphony_yaml, message}} ->
              {:error, "Invalid symphony.yaml: #{message}"}

            {:error, other} ->
              {:error, "Invalid process config: #{inspect(other)}"}
          end
        else
          run(Path.expand("WORKFLOW.md"), deps)
        end
    end
  end

  defp resolve_and_run_workflow([workflow_path], deps) do
    run(workflow_path, deps)
  end

  defp has_top_level_projects_key?(yaml) when is_map(yaml) do
    Map.has_key?(yaml, "projects") or Map.has_key?(yaml, :projects)
  end

  @spec run(String.t(), deps()) :: :ok | {:error, String.t()}
  def run(workflow_path, deps) do
    expanded_path = Path.expand(workflow_path)

    if deps.file_regular?.(expanded_path) do
      :ok = deps.set_workflow_file_path.(expanded_path)

      case deps.ensure_all_started.() do
        {:ok, _started_apps} ->
          :ok

        {:error, reason} ->
          {:error, "Failed to start Symphony with workflow #{expanded_path}: #{inspect(reason)}"}
      end
    else
      {:error, "Workflow file not found: #{expanded_path}"}
    end
  end

  @spec usage_message() :: String.t()
  def usage_message do
    "Usage: symphony [--help|-h] [--logs-root <path>] [--config <path>] [--port <port>] [--host <host>] " <>
      "[--project <project-id>.<field> <value>] ... [path-to-WORKFLOW.md]"
  end

  @spec runtime_deps() :: deps()
  defp runtime_deps do
    %{
      file_regular?: &File.regular?/1,
      set_workflow_file_path: &SymphonyElixir.Workflow.set_workflow_file_path/1,
      set_logs_root: &set_logs_root/1,
      set_server_port_override: &set_server_port_override/1,
      set_server_host_override: &set_server_host_override/1,
      set_config_arg: &set_config_arg/1,
      ensure_all_started: fn -> Application.ensure_all_started(:symphony_elixir) end
    }
  end

  defp maybe_set_logs_root(opts, deps) do
    case Keyword.get_values(opts, :logs_root) do
      [] ->
        :ok

      values ->
        logs_root = values |> List.last() |> String.trim()

        if logs_root == "" do
          {:error, usage_message()}
        else
          :ok = deps.set_logs_root.(Path.expand(logs_root))
        end
    end
  end

  defp require_guardrails_acknowledgement(opts) do
    if Keyword.get(opts, @acknowledgement_switch, false) do
      :ok
    else
      {:error, acknowledgement_banner()}
    end
  end

  @spec acknowledgement_banner() :: String.t()
  defp acknowledgement_banner do
    lines = [
      "This Symphony implementation is a low key engineering preview.",
      "Codex will run without any guardrails.",
      "SymphonyElixir is not a supported product and is presented as-is.",
      "To proceed, start with `--i-understand-that-this-will-be-running-without-the-usual-guardrails` CLI argument"
    ]

    width = Enum.max(Enum.map(lines, &String.length/1))
    border = String.duplicate("─", width + 2)
    top = "╭" <> border <> "╮"
    bottom = "╰" <> border <> "╯"
    spacer = "│ " <> String.duplicate(" ", width) <> " │"

    content =
      [
        top,
        spacer
        | Enum.map(lines, fn line ->
            "│ " <> String.pad_trailing(line, width) <> " │"
          end)
      ] ++ [spacer, bottom]

    [
      IO.ANSI.red(),
      IO.ANSI.bright(),
      Enum.join(content, "\n"),
      IO.ANSI.reset()
    ]
    |> IO.iodata_to_binary()
  end

  defp set_logs_root(logs_root) do
    Application.put_env(:symphony_elixir, :log_file, LogFile.default_log_file(logs_root))
    :ok
  end

  defp maybe_set_server_port(opts, deps) do
    case Keyword.get_values(opts, :port) do
      [] ->
        :ok

      values ->
        port = List.last(values)

        if is_integer(port) and port >= 0 do
          :ok = deps.set_server_port_override.(port)
        else
          {:error, usage_message()}
        end
    end
  end

  defp set_server_port_override(port) when is_integer(port) and port >= 0 do
    Application.put_env(:symphony_elixir, :server_port_override, port)
    :ok
  end

  defp maybe_set_server_host(opts, deps) do
    case Keyword.get_values(opts, :host) do
      [] ->
        :ok

      values ->
        host = values |> List.last() |> String.trim()

        if host == "" do
          {:error, usage_message()}
        else
          :ok = deps.set_server_host_override.(host)
        end
    end
  end

  defp set_server_host_override(host) when is_binary(host) do
    Application.put_env(:symphony_elixir, :server_host_override, host)
    :ok
  end

  defp maybe_set_config_arg(opts, deps) do
    case Keyword.get_values(opts, :config) do
      [] ->
        :ok

      values ->
        config_path = values |> List.last() |> String.trim()

        if config_path == "" do
          {:error, usage_message()}
        else
          :ok = deps.set_config_arg.(Path.expand(config_path))
        end
    end
  end

  defp set_config_arg(config_path) when is_binary(config_path) do
    Application.put_env(:symphony_elixir, :config_arg, config_path)
    :ok
  end

  @spec wait_for_shutdown() :: no_return()
  defp wait_for_shutdown do
    case Process.whereis(SymphonyElixir.Supervisor) do
      nil ->
        IO.puts(:stderr, "Symphony supervisor is not running")
        System.halt(1)

      pid ->
        ref = Process.monitor(pid)

        receive do
          {:DOWN, ^ref, :process, ^pid, reason} ->
            case reason do
              :normal -> System.halt(0)
              _ -> System.halt(1)
            end
        end
    end
  end
end
