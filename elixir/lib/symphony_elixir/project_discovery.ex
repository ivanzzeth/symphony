defmodule SymphonyElixir.ProjectDiscovery do
  @moduledoc """
  Scans a projects directory for subdirectories containing WORKFLOW.md files.
  Returns a list of project descriptors for multi-project orchestration.
  """

  @workflow_file_name "WORKFLOW.md"

  @type project :: %{
          name: String.t(),
          path: Path.t(),
          workflow_path: Path.t()
        }

  @doc """
  Discovers projects under `projects_dir`.

  Returns `{:ok, [project()]}` or `{:error, reason}`.
  """
  @spec discover(String.t()) :: {:ok, [project()]} | {:error, term()}
  def discover(projects_dir) do
    expanded = Path.expand(projects_dir)

    with {:ok, entries} <- list_dir(expanded) do
      projects =
        entries
        |> Enum.filter(&dir?(&1, expanded))
        |> Enum.map(&build_project(&1, expanded))
        |> Enum.filter(fn %{workflow_path: wp} -> File.regular?(wp) end)
        |> Enum.sort_by(& &1.name)

      {:ok, projects}
    end
  end

  defp list_dir(path) do
    case File.ls(path) do
      {:ok, entries} -> {:ok, entries}
      {:error, reason} -> {:error, {:invalid_projects_dir, path, reason}}
    end
  end

  defp dir?(entry, parent) do
    File.dir?(Path.join(parent, entry))
  end

  defp build_project(name, parent) do
    path = Path.join(parent, name)
    workflow_path = Path.join(path, @workflow_file_name)

    %{
      name: name,
      path: path,
      workflow_path: workflow_path
    }
  end
end
