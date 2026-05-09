defmodule SymphonyElixir.ProjectNaming do
  @moduledoc false

  @registry SymphonyElixir.ProjectProcessRegistry

  @spec registry() :: atom()
  def registry, do: @registry

  @spec via(String.t(), atom()) :: {:via, Registry, {atom(), {String.t(), atom()}}}
  def via(project_id, role) when is_binary(project_id) and is_atom(role) do
    {:via, Registry, {@registry, {project_id, role}}}
  end
end
