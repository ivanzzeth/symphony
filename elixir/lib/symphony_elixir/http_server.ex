defmodule SymphonyElixir.HttpServer do
  @moduledoc """
  Compatibility facade that starts the Phoenix observability endpoint when enabled.
  """

  alias SymphonyElixir.{Config, Orchestrator, Rescue, TestEnv}
  alias SymphonyElixirWeb.Endpoint

  @secret_key_bytes 48

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  @spec start_link(keyword()) :: GenServer.on_start() | :ignore
  def start_link(opts \\ []) do
    case Keyword.get(opts, :port, Config.server_port()) do
      port when is_integer(port) and port >= 0 ->
        host = Keyword.get(opts, :host, Config.server_host())
        orchestrator = Keyword.get(opts, :orchestrator, Orchestrator)
        snapshot_timeout_ms = Keyword.get(opts, :snapshot_timeout_ms, 15_000)

        with {:ok, ip} <- parse_host(host) do
          endpoint_opts = [
            server: true,
            http: [ip: ip, port: port],
            url: [host: normalize_host(host)],
            orchestrator: orchestrator,
            snapshot_timeout_ms: snapshot_timeout_ms,
            secret_key_base: secret_key_base()
          ]

          endpoint_config =
            :symphony_elixir
            |> Application.get_env(Endpoint, [])
            |> Keyword.merge(endpoint_opts)

          Application.put_env(:symphony_elixir, Endpoint, endpoint_config)
          Endpoint.start_link()
        end

      _ ->
        :ignore
    end
  end

  @spec bound_port(term()) :: non_neg_integer() | nil
  def bound_port(_server \\ __MODULE__) do
    # Test-only env keys; see `http_server_test.exs` (not used in production).
    if Application.get_env(:symphony_elixir, :http_server_bound_port_force_raise, false) do
      raise RuntimeError, "symphony test: force bound_port rescue path"
    end

    case Application.get_env(:symphony_elixir, :http_server_bound_port_test_mode) do
      :raise -> raise RuntimeError, "HttpServer.bound_port test mode (raise)"
      {:exit, reason} -> exit(reason)
      _ -> :ok
    end

    case phoenix_http_server_info() do
      {:ok, {_ip, port}} when is_integer(port) -> port
      _ -> nil
    end
  rescue
    error ->
      Rescue.log_warning("HttpServer.bound_port/1: failed, returning nil", error, __STACKTRACE__)
      nil
  catch
    :exit, reason ->
      Rescue.log_exit_warning("HttpServer.bound_port/1: failed (exit), returning nil", reason)
      nil
  end

  defp phoenix_http_server_info do
    if TestEnv.active?() do
      case Application.get_env(:symphony_elixir, :http_server_phoenix_http_server_info_stub) do
        fun when is_function(fun, 0) -> fun.()
        _ -> Bandit.PhoenixAdapter.server_info(Endpoint, :http)
      end
    else
      Bandit.PhoenixAdapter.server_info(Endpoint, :http)
    end
  end

  defp parse_host({_, _, _, _} = ip), do: {:ok, ip}
  defp parse_host({_, _, _, _, _, _, _, _} = ip), do: {:ok, ip}

  defp parse_host(host) when is_binary(host) do
    charhost = String.to_charlist(host)

    case :inet.parse_address(charhost) do
      {:ok, ip} ->
        {:ok, ip}

      {:error, _reason} ->
        case :inet.getaddr(charhost, :inet) do
          {:ok, ip} -> {:ok, ip}
          {:error, _reason} -> :inet.getaddr(charhost, :inet6)
        end
    end
  end

  defp normalize_host(host) when host in ["", nil], do: "127.0.0.1"
  defp normalize_host(host) when is_binary(host), do: host
  defp normalize_host(host), do: to_string(host)

  defp secret_key_base do
    Base.encode64(:crypto.strong_rand_bytes(@secret_key_bytes), padding: false)
  end
end
