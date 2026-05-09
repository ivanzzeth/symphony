defmodule SymphonyElixir.Config.Context do
  @moduledoc false

  @workflow_store_key :symphony_workflow_store

  @spec put_workflow_store(term()) :: term() | nil
  def put_workflow_store(store) do
    Process.put(@workflow_store_key, store)
  end

  @spec delete_workflow_store() :: term() | nil
  def delete_workflow_store do
    Process.delete(@workflow_store_key)
  end

  @spec workflow_store() :: term() | nil
  def workflow_store do
    Process.get(@workflow_store_key)
  end
end
