defmodule SymphonyElixir.CodingAgent do
  @moduledoc """
  Behaviour for coding agent adapters (Codex, Claude Code, Cursor).
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
end
