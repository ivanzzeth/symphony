defmodule SymphonyElixirWeb.ObservabilityPubSub do
  @moduledoc """
  PubSub helpers for observability dashboard updates.

  Topics are scoped per project (`project:<project_id>`) so subscribers only
  receive events for their project.
  """

  @pubsub SymphonyElixir.PubSub
  @update_message :observability_updated

  @spec topic(String.t()) :: String.t()
  def topic(project_id) when is_binary(project_id), do: "project:#{project_id}"

  @spec subscribe(String.t() | nil) :: :ok | {:error, term()}
  def subscribe(project_id \\ nil) do
    Phoenix.PubSub.subscribe(@pubsub, topic(resolve_project_id(project_id)))
  end

  @spec unsubscribe(String.t()) :: :ok
  def unsubscribe(project_id) when is_binary(project_id) do
    Phoenix.PubSub.unsubscribe(@pubsub, topic(project_id))
  end

  @spec broadcast_update(String.t() | nil) :: :ok
  def broadcast_update(project_id \\ nil) do
    id = resolve_project_id(project_id)

    case Process.whereis(@pubsub) do
      pid when is_pid(pid) ->
        Phoenix.PubSub.broadcast(@pubsub, topic(id), @update_message)

      _ ->
        :ok
    end
  end

  defp resolve_project_id(nil) do
    Application.get_env(:symphony_elixir, :primary_project_id) || "default"
  end

  defp resolve_project_id(project_id) when is_binary(project_id), do: project_id
end
