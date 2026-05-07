defmodule SymphonyElixir.CodingAgent do
  @moduledoc """
  Behaviour for coding agent adapters (Codex, Claude Code, Cursor).

  ## Adapter Selection

  `adapter/0` reads `Config.settings!().agent.kind` and returns the
  corresponding adapter module:

    * `"codex"`  — `SymphonyElixir.Codex.AppServer` (JSON-RPC 2.0 over stdio)
    * `"claude"` — `SymphonyElixir.Claude.Adapter` (CLI with `--print --output-format stream-json`)
    * `"cursor"` — `SymphonyElixir.Cursor.Adapter` (CLI with `agent --print --output-format stream-json`)

  The config schema validates `agent.kind` against `["codex", "claude", "cursor"]`
  and defaults to `"codex"`.

  ## Adding a New Backend

  1. Create a module (e.g. `SymphonyElixir.MyBackend.Adapter`) that
     implements `@behaviour SymphonyElixir.CodingAgent` with the three
     required callbacks: `start_session/2`, `run_turn/4`, `stop_session/1`.
  2. Add the new `agent.kind` value to the `validate_inclusion` list in
     `Config.Schema.Agent.changeset/2`.
  3. Add a clause to `CodingAgent.adapter/0` mapping the kind string to
     your module.
  4. Write tests following the pattern in `coding_agent_test.exs`.
  """

  alias SymphonyElixir.Config

  @typedoc """
  Session state carried across turns. Shape is adapter-specific.
  """
  @type session :: map()

  @doc """
  Start an agent session in the given workspace.
  May open a long-lived subprocess (Codex) or just set up session state (Claude/Cursor).
  """
  @callback start_session(workspace :: Path.t(), opts :: keyword()) ::
              {:ok, session()} | {:error, term()}

  @doc """
  Run a single turn with the given prompt.
  Returns the turn result and emits events via on_message callback.
  """
  @callback run_turn(session(), prompt :: String.t(), issue :: map(), opts :: keyword()) ::
              {:ok, map()} | {:error, term()}

  @doc """
  Stop the agent session and clean up resources.
  """
  @callback stop_session(session()) :: :ok

  @spec adapter() :: module()
  def adapter do
    case Config.settings!().agent.kind do
      "codex" -> SymphonyElixir.Codex.AppServer
      "claude" -> SymphonyElixir.Claude.Adapter
      "cursor" -> SymphonyElixir.Cursor.Adapter
    end
  end

  @known_agent_kinds ~w(codex claude cursor)

  @doc """
  Human-readable label for `agent.kind` (dashboards and APIs).
  """
  @spec kind_display_label(String.t()) :: String.t()
  def kind_display_label(kind) when kind in @known_agent_kinds do
    case kind do
      "codex" -> "Codex"
      "claude" -> "Claude Code"
      "cursor" -> "Cursor"
    end
  end

  def kind_display_label(kind) when is_binary(kind) do
    kind
    |> String.trim()
    |> case do
      "" -> "Unknown"
      value -> humanize_unknown_agent_kind(value)
    end
  end

  def kind_display_label(_), do: "Unknown"

  defp humanize_unknown_agent_kind(value) do
    value
    |> String.replace(~r/[-_]/, " ")
    |> String.split(~r/\s+/, trim: true)
    |> Enum.map_join(" ", &String.capitalize/1)
  end
end
