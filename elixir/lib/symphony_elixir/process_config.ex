defmodule SymphonyElixir.ProcessConfig do
  @moduledoc """
  Process-level configuration loaded from `symphony.yaml`.

  Resolution order:
    1. CLI flags (`--port`, `--host`)
    2. Environment variables (`SYMPHONY_PORT`, `SYMPHONY_HOST`)
    3. `symphony.yaml` file values
    4. Built-in defaults

  Config file path resolution:
    1. CLI `--config <path>` argument
    2. `SYMPHONY_CONFIG_PATH` environment variable
    3. `~/.config/symphony/symphony.yaml`

  Missing file is not an error — defaults are used.
  """

  require Logger

  @default_host "127.0.0.1"
  @default_dashboard_enabled true
  @default_refresh_ms 1_000
  @default_render_interval_ms 16

  defstruct server: %{port: nil, host: @default_host},
            observability: %{
              dashboard_enabled: @default_dashboard_enabled,
              refresh_ms: @default_refresh_ms,
              render_interval_ms: @default_render_interval_ms
            }

  @type t :: %__MODULE__{
          server: %{port: non_neg_integer() | nil, host: String.t()},
          observability: %{
            dashboard_enabled: boolean(),
            refresh_ms: pos_integer(),
            render_interval_ms: pos_integer()
          }
        }

  @doc """
  Resolve the effective config file path.
  """
  @spec config_path(String.t() | nil) :: Path.t() | nil
  def config_path(cli_arg \\ nil) do
    cli_arg || System.get_env("SYMPHONY_CONFIG_PATH") || default_config_path()
  end

  @doc """
  Load and resolve the effective process config.
  """
  @spec load(String.t() | nil) :: {:ok, t()} | {:error, term()}
  def load(cli_config_arg \\ nil) do
    path = config_path(cli_config_arg)
    yaml_config = load_yaml_config(path)
    {:ok, merge_with_defaults(yaml_config)}
  end

  @doc false
  @spec load_yaml_config(Path.t() | nil) :: map()
  def load_yaml_config(nil), do: %{}

  def load_yaml_config(path) when is_binary(path) do
    case File.read(path) do
      {:ok, content} ->
        case YamlElixir.read_from_string(content) do
          {:ok, decoded} when is_map(decoded) -> decoded
          {:ok, _} -> %{}
          {:error, _reason} -> %{}
        end

      {:error, :enoent} ->
        %{}

      {:error, reason} ->
        Logger.warning("Failed to read process config file #{path}: #{inspect(reason)}")
        %{}
    end
  end

  defp merge_with_defaults(yaml_config) when is_map(yaml_config) do
    %__MODULE__{
      server: %{
        port: resolve_port(yaml_config),
        host: resolve_host(yaml_config)
      },
      observability: %{
        dashboard_enabled: resolve_dashboard_enabled(yaml_config),
        refresh_ms: resolve_refresh_ms(yaml_config),
        render_interval_ms: resolve_render_interval_ms(yaml_config)
      }
    }
  end

  defp resolve_port(yaml_config) when is_map(yaml_config) do
    cli_port = Application.get_env(:symphony_elixir, :server_port_override)

    cond do
      is_integer(cli_port) and cli_port >= 0 -> cli_port
      env_port() -> env_port()
      true -> valid_port(get_in(yaml_config, ["server", "port"]))
    end
  end

  defp resolve_host(yaml_config) when is_map(yaml_config) do
    cli_host = Application.get_env(:symphony_elixir, :server_host_override)

    cond do
      is_binary(cli_host) and cli_host != "" -> cli_host
      env_host() -> env_host()
      true -> valid_host(get_in(yaml_config, ["server", "host"])) || @default_host
    end
  end

  defp resolve_dashboard_enabled(yaml_config) when is_map(yaml_config) do
    case get_in(yaml_config, ["observability", "dashboard_enabled"]) do
      val when is_boolean(val) -> val
      _ -> @default_dashboard_enabled
    end
  end

  defp resolve_refresh_ms(yaml_config) when is_map(yaml_config) do
    case get_in(yaml_config, ["observability", "refresh_ms"]) do
      val when is_integer(val) and val > 0 -> val
      _ -> @default_refresh_ms
    end
  end

  defp resolve_render_interval_ms(yaml_config) when is_map(yaml_config) do
    case get_in(yaml_config, ["observability", "render_interval_ms"]) do
      val when is_integer(val) and val > 0 -> val
      _ -> @default_render_interval_ms
    end
  end

  defp valid_port(val) when is_integer(val) and val >= 0, do: val
  defp valid_port(_), do: nil

  defp valid_host(val) when is_binary(val) and val != "", do: val
  defp valid_host(_), do: nil

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

  defp default_config_path do
    Path.join(System.user_home!(), ".config/symphony/symphony.yaml")
  end
end
