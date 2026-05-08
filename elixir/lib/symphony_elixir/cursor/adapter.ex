defmodule SymphonyElixir.Cursor.Adapter do
  @moduledoc """
  CodingAgent adapter for Cursor Agent CLI.

  Each turn opens a fresh CLI process using `cursor agent --print --output-format stream-json`
  and reads stream-json line by line.
  """
  @behaviour SymphonyElixir.CodingAgent

  require Logger
  alias SymphonyElixir.{Config, Rescue, SSH}

  @default_port_line_bytes 1_048_576

  @impl true
  def start_session(workspace, _opts) do
    session_id = generate_session_id()
    {:ok, %{session_id: session_id, workspace: workspace, resume_id: nil}}
  end

  @impl true
  def run_turn(session, prompt, _issue, opts \\ []) do
    on_message = Keyword.get(opts, :on_message, &default_on_message/1)
    worker_host = Keyword.get(opts, :worker_host)
    timeout_ms = Config.settings!().agent.stream_timeout_ms

    cli_args = build_cli_args(session, prompt)

    with {:ok, port} <- open_cursor_port(session.workspace, cli_args, worker_host) do
      try do
        receive_stream(port, on_message, session, %{input_tokens: 0, output_tokens: 0}, timeout_ms, "")
      after
        close_port(port)
      end
    end
  end

  @impl true
  def stop_session(_session), do: :ok

  # --- private ---

  defp generate_session_id do
    "#{:erlang.unique_integer([:positive])}-#{System.system_time(:millisecond)}"
  end

  defp build_cli_args(session, prompt) do
    # Split the full agent.command (e.g. "stdbuf -oL -eL /path/cursor") so the
    # "agent" subcommand comes after the real CLI binary, not after a stdbuf prefix.
    command_parts =
      Config.settings!().agent.command
      |> String.split(~r/\s+/, trim: true)

    base =
      command_parts ++
        [
          "agent",
          "--print",
          "--output-format",
          "stream-json",
          "--force",
          "--trust",
          "--workspace",
          session.workspace
        ]

    session_arg =
      if session.resume_id do
        ["--resume", session.resume_id]
      else
        []
      end

    escaped_prompt = SSH.shell_escape(prompt)

    (base ++ session_arg ++ ["--", escaped_prompt])
    |> Enum.join(" ")
    |> then(&"exec #{&1}")
  end

  defp open_cursor_port(workspace, cli_args, nil) do
    case System.find_executable("bash") do
      nil ->
        {:error, :bash_not_found}

      executable ->
        port =
          Port.open(
            {:spawn_executable, String.to_charlist(executable)},
            [
              :binary,
              :exit_status,
              :stderr_to_stdout,
              args: [~c"-lc", String.to_charlist(cli_args)],
              cd: String.to_charlist(workspace),
              env: system_env_charlists(),
              line: port_line_bytes()
            ]
          )

        {:ok, port}
    end
  end

  defp open_cursor_port(workspace, cli_args, worker_host) when is_binary(worker_host) do
    remote_command = "cd #{SSH.shell_escape(workspace)} && exec #{cli_args}"
    SSH.start_port(worker_host, remote_command, line: port_line_bytes())
  end

  defp system_env_charlists do
    System.get_env()
    |> Enum.map(fn {k, v} -> {String.to_charlist(k), String.to_charlist(v)} end)
  end

  defp receive_stream(port, on_message, session, usage, timeout_ms, pending_line) do
    receive do
      {^port, {:data, {:eol, chunk}}} ->
        line = pending_line <> to_string(chunk)

        case handle_line(line, on_message, session, usage) do
          {:complete, result} ->
            result

          {:continue, new_usage, new_session} ->
            receive_stream(port, on_message, new_session, new_usage, timeout_ms, "")
        end

      {^port, {:data, {:noeol, chunk}}} ->
        frag = IO.iodata_to_binary(chunk)
        n = byte_size(frag)
        plen = byte_size(pending_line)
        buf = port_line_bytes()

        Logger.warning(
          "Cursor adapter: stream-json line exceeded port line buffer (#{buf} bytes) without newline; " <>
            "buffering partial segment (#{n} bytes, pending #{plen} bytes)"
        )

        emit_message(on_message, :buffer_exceeded, %{
          adapter: :cursor,
          chunk_bytes: n,
          pending_bytes: plen,
          port_line_bytes: buf
        })

        receive_stream(port, on_message, session, usage, timeout_ms, pending_line <> frag)

      {^port, {:exit_status, status}} ->
        {:error, {:port_exit, status}}
    after
      timeout_ms ->
        emit_message(on_message, :turn_timeout, %{timeout_ms: timeout_ms, adapter: :cursor})
        {:error, :turn_timeout}
    end
  end

  defp handle_line(line, on_message, session, usage) do
    case Jason.decode(line) do
      {:ok, %{"type" => "system", "subtype" => "init"} = payload} ->
        sid = Map.get(payload, "session_id", session.session_id)

        emit_message(on_message, :session_started, %{
          session_id: sid
        })

        {:continue, usage, %{session | session_id: sid, resume_id: sid}}

      {:ok, %{"type" => "assistant"} = payload} ->
        emit_message(on_message, :notification, %{
          payload: payload
        })

        {:continue, usage, session}

      {:ok, %{"type" => "user"} = payload} ->
        emit_message(on_message, :notification, %{
          payload: payload
        })

        {:continue, usage, session}

      {:ok, %{"type" => "result", "is_error" => false} = payload} ->
        final_usage = accumulate_usage(payload, usage)

        emit_message(on_message, :turn_completed, %{
          payload: payload,
          usage: final_usage
        })

        {:complete,
         {:ok,
          %{
            input_tokens: final_usage.input_tokens,
            output_tokens: final_usage.output_tokens,
            resume_id: session.resume_id
          }}}

      {:ok, %{"type" => "result", "is_error" => true} = payload} ->
        emit_message(on_message, :turn_failed, %{
          payload: payload
        })

        {:complete, {:error, {:turn_failed, payload}}}

      {:ok, payload} ->
        emit_message(on_message, :notification, %{
          payload: payload
        })

        {:continue, usage, session}

      {:error, _reason} ->
        emit_message(on_message, :malformed, %{
          payload: line,
          raw: line
        })

        {:continue, usage, session}
    end
  end

  defp accumulate_usage(payload, current_usage) do
    usage = get_in(payload, ["message", "usage"]) || Map.get(payload, "usage") || %{}

    input = resolve_token_count(usage, ["inputTokens", "input_tokens"])
    output = resolve_token_count(usage, ["outputTokens", "output_tokens"])

    %{
      input_tokens: current_usage.input_tokens + input,
      output_tokens: current_usage.output_tokens + output
    }
  end

  defp resolve_token_count(usage, keys) do
    Enum.find_value(keys, 0, fn key ->
      case Map.get(usage, key) do
        nil -> nil
        val -> int_or(val, 0)
      end
    end)
  end

  defp int_or(nil, default), do: default
  defp int_or(value, _default) when is_integer(value), do: value

  defp int_or(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {num, _} -> num
      :error -> default
    end
  end

  defp port_line_bytes do
    Application.get_env(:symphony_elixir, :coding_agent_port_line_bytes, @default_port_line_bytes)
  end

  defp emit_message(on_message, event, details) do
    message =
      details
      |> Map.put(:event, event)
      |> Map.put(:timestamp, DateTime.utc_now())

    on_message.(message)
  end

  defp default_on_message(_message), do: :ok

  defp close_port(port) when is_port(port), do: Rescue.close_port_if_open(port)
end
