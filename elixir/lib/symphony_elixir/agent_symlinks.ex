defmodule SymphonyElixir.AgentSymlinks do
  @moduledoc """
  Manages .claude/ -> .agents/ and .cursor/ -> .agents/ symlinks in workspaces
  per SPEC V1.1 Section 4.3.

  .agents/ is the single source of truth for agent definitions, skills, and MCP
  config.  .claude/ and .cursor/ should be symlinks to .agents/ so that all CLIs
  see consistent configuration.
  """

  require Logger
  alias SymphonyElixir.SSH

  @symlinks [
    {".claude", ".agents"},
    {".cursor", ".agents"},
    {".codex", ".agents"}
  ]

  @doc """
  Ensures symlinks in a workspace point to .agents/. Always returns :ok;
  failures are logged but never fatal.
  """
  @spec manage(String.t(), String.t() | nil) :: :ok
  def manage(workspace, worker_host \\ nil)

  def manage(workspace, nil) do
    Logger.debug("Managing agent symlinks in workspace=#{workspace}")

    case ensure_agents_dir(workspace) do
      :ok ->
        Enum.each(@symlinks, fn {name, target} ->
          manage_local_symlink(Path.join(workspace, name), target, workspace)
        end)

        :ok

      {:error, _reason} ->
        :ok
    end
  end

  def manage(workspace, worker_host) when is_binary(worker_host) do
    Logger.debug("Managing agent symlinks in remote workspace=#{workspace} worker_host=#{worker_host}")

    script =
      @symlinks
      |> Enum.map(fn {name, target} ->
        link_path = "$workspace/#{name}"
        target_path = target

        [
          "if [ -L \"#{link_path}\" ]; then",
          "  current=$(readlink \"#{link_path}\")",
          "  if [ \"$current\" != \"#{target_path}\" ]; then",
          "    rm -f \"#{link_path}\"",
          "    ln -s \"#{target_path}\" \"#{link_path}\"",
          "  fi",
          "elif [ -d \"#{link_path}\" ]; then",
          "  echo \"[symphony] real directory at #{link_path}; skipping symlink\" >&2",
          "elif [ -e \"#{link_path}\" ]; then",
          "  echo \"[symphony] non-directory at #{link_path}; skipping symlink\" >&2",
          "else",
          "  mkdir -p \"$workspace/.agents\"",
          "  ln -s \"#{target_path}\" \"#{link_path}\"",
          "fi"
        ]
        |> Enum.join("\n")
      end)
      |> Enum.join("\n")

    full_script = [
      "set -eu",
      SSH.remote_shell_assign("workspace", workspace),
      script
    ]
    |> Enum.join("\n")

    case SSH.run(worker_host, full_script, stderr_to_stdout: true) do
      {:ok, {_output, 0}} -> :ok
      {:ok, {output, status}} ->
        Logger.warning("Remote symlink management failed for #{workspace} on #{worker_host} status=#{status}: #{IO.iodata_to_binary(output)}")
        :ok
      {:error, reason} ->
        Logger.warning("Remote symlink management failed for #{workspace} on #{worker_host}: #{inspect(reason)}")
        :ok
    end
  end

  @doc """
  Reconciles symlinks in all existing workspaces under the given root.
  Always returns :ok; failures are logged but never fatal.
  """
  @spec reconcile_all(String.t()) :: :ok
  def reconcile_all(workspace_root) do
    Logger.info("Reconciling agent symlinks in all workspaces under #{workspace_root}")

    case File.ls(workspace_root) do
      {:ok, entries} ->
        entries
        |> Enum.each(fn entry ->
          path = Path.join(workspace_root, entry)

          if File.dir?(path) and not String.starts_with?(entry, ".") do
            manage(path)
          end
        end)

        :ok

      {:error, :enoent} ->
        Logger.debug("Workspace root #{workspace_root} does not exist yet; skipping symlink reconciliation")
        :ok

      {:error, reason} ->
        Logger.warning("Cannot list workspace root #{workspace_root} for symlink reconciliation: #{inspect(reason)}")
        :ok
    end
  end

  defp ensure_agents_dir(workspace) do
    agents_dir = Path.join(workspace, ".agents")

    cond do
      File.dir?(agents_dir) ->
        :ok

      File.exists?(agents_dir) ->
        Logger.warning("Non-directory at #{agents_dir}; skipping symlink management in #{workspace}")
        {:error, :agents_path_not_directory}

      true ->
        case File.mkdir(agents_dir) do
          :ok ->
            :ok

          {:error, reason} ->
            Logger.warning("Cannot create .agents/ at #{agents_dir}: #{inspect(reason)}")
            {:error, reason}
        end
    end
  end

  defp manage_local_symlink(link_path, target, workspace) do
    case File.lstat(link_path) do
      {:ok, %File.Stat{type: :symlink}} ->
        case File.read_link(link_path) do
          {:ok, ^target} ->
            :ok

          {:ok, wrong_target} ->
            Logger.info("Repairing symlink #{link_path} (was -> #{wrong_target}, should -> #{target})")
            File.rm_rf!(link_path)
            create_link(link_path, target, workspace)

          {:error, reason} ->
            Logger.warning("Cannot read symlink #{link_path}: #{inspect(reason)}; attempting repair")
            File.rm_rf!(link_path)
            create_link(link_path, target, workspace)
        end

      {:ok, %File.Stat{type: :directory}} ->
        Logger.warning("Real directory exists at #{link_path}; skipping symlink creation")

      {:ok, _} ->
        Logger.warning("Non-symlink file at #{link_path}; skipping symlink creation")

      {:error, :enoent} ->
        create_link(link_path, target, workspace)

      {:error, reason} ->
        Logger.warning("Cannot stat #{link_path}: #{inspect(reason)}; skipping")
    end
  end

  defp create_link(link_path, target, _workspace) do
    case File.ln_s(target, link_path) do
      :ok ->
        :ok

      {:error, :eexist} ->
        manage_local_symlink(link_path, target, nil)

      {:error, reason} ->
        Logger.warning("Cannot create symlink #{link_path} -> #{target}: #{inspect(reason)}")
    end
  end
end
