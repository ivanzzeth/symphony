defmodule SymphonyElixir.Init do
  @moduledoc """
  `symphony init` — bootstrap `.agents/` directory for a Symphony-managed project.

  Reads from the escript-embedded `priv/agents/` and `priv/templates/init/` directories,
  copies files to the target project, and writes a `.symphony-manifest.yaml` for upgrade
  tracking.

  ## Classify files (two categories)

  - **managed** (`skills/symphony-*/*`, `agents/symphony-*.md`): owned by Symphony.
    `--upgrade` overwrites these.
  - **preserved** (`WORKFLOW.md`, `AGENTS.md`, `.agents/symphony-vars.yaml`,
    `.agents/.symphony-manifest.yaml`): user-customizable. `--upgrade` skips;
    only `--force` overwrites.

  Files without the `symphony-` prefix are never touched.
  """

  @doc """
  Run `symphony init` against `target_dir`.

  ## Options

    * `:target_dir` — project root (default: `.`)
    * `:source_root` — embedded source root (default: `priv` bundled in escript)
    * `:upgrade` — boolean, allow re-initializing existing `.agents/`
    * `:force` — boolean, overwrite preserved files too
  """
  @spec run(keyword()) :: :ok | {:error, String.t()}
  def run(opts \\ []) do
    target_dir = Keyword.get(opts, :target_dir, File.cwd!())
    source_root = Keyword.get(opts, :source_root, default_source_root())
    upgrade? = Keyword.get(opts, :upgrade, false)
    force? = Keyword.get(opts, :force, false)

    agents_dir = Path.join(target_dir, ".agents")
    manifest_path = Path.join(agents_dir, ".symphony-manifest.yaml")

    with :ok <- check_preconditions(agents_dir, upgrade?, force?),
         :ok <- create_directories(agents_dir) do
      # 1. Copy managed files (skills/symphony-*/, agents/symphony-*.md)
      managed_files = discover_managed_files(source_root)
      existing_manifest = read_manifest(manifest_path)

      new_files =
        Enum.reduce(managed_files, %{}, fn {rel_path, src_abs}, acc ->
          dest = Path.join(agents_dir, rel_path)
          # Always overwrite managed files on init
          File.mkdir_p!(Path.dirname(dest))
          File.cp!(src_abs, dest)
          Map.put(acc, rel_path, %{"category" => "managed"})
        end)

      # 2. Copy preserved templates to target root
      preserved_files = discover_preserved_files(source_root)

      new_preserved =
        Enum.reduce(preserved_files, %{}, fn {rel_path, src_abs}, acc ->
          dest = Path.join(target_dir, rendered_dest(rel_path))
          rendered_rel = rendered_dest(rel_path)

          should_write? =
            if force? do
              true
            else
              case existing_manifest do
                %{"files" => files} -> not Map.has_key?(files, rendered_rel)
                _ -> true
              end
            end

          if should_write? do
            File.mkdir_p!(Path.dirname(dest))
            File.cp!(src_abs, dest)
          end

          Map.put(acc, rendered_rel, %{"category" => "preserved"})
        end)

      # 3. Write vars template
      vars_src = Path.join(source_root, "symphony-vars.yaml")
      vars_dest = Path.join(agents_dir, "symphony-vars.yaml")
      vars_rel = ".agents/symphony-vars.yaml"

      if File.regular?(vars_src) do
        should_write_vars? =
          if force? do
            true
          else
            case existing_manifest do
              %{"files" => files} -> not Map.has_key?(files, vars_rel)
              _ -> true
            end
          end

        if should_write_vars? do
          File.mkdir_p!(Path.dirname(vars_dest))
          File.cp!(vars_src, vars_dest)
        end
      end

      # 4. Create symlinks
      create_symlinks(target_dir)

      # 5. Write manifest
      new_preserved = Map.put(new_preserved, vars_rel, %{"category" => "preserved"})
      merged = Map.merge(new_files, new_preserved)
      version = Application.spec(:symphony_elixir, :vsn) || "0.0.0"
      write_manifest(manifest_path, version, merged)
    end
  end

  defp check_preconditions(_agents_dir, upgrade?, _force?) when upgrade?, do: :ok
  defp check_preconditions(_agents_dir, _upgrade?, force?) when force?, do: :ok

  defp check_preconditions(agents_dir, _upgrade?, _force?) do
    if File.dir?(agents_dir) do
      {:error,
       ".agents/ already exists in target directory. Use --upgrade to refresh managed files " <>
         "or --force to overwrite preserved files too."}
    else
      :ok
    end
  end

  defp create_directories(agents_dir) do
    dirs = [
      agents_dir,
      Path.join(agents_dir, "skills"),
      Path.join(agents_dir, "agents"),
      Path.join(agents_dir, "templates")
    ]

    Enum.each(dirs, &File.mkdir_p!/1)
    :ok
  end

  defp discover_managed_files(source_root) do
    skills_dir = Path.join(source_root, "skills")
    agents_dir = Path.join(source_root, "agents")

    skill_files =
      if File.dir?(skills_dir) do
        walk_dir(skills_dir, "skills")
      else
        []
      end

    agent_files =
      if File.dir?(agents_dir) do
        walk_dir(agents_dir, "agents")
      else
        []
      end

    (skill_files ++ agent_files)
    |> Enum.filter(fn {rel, _} ->
      String.starts_with?(Path.basename(rel), "symphony-") or
        String.contains?(rel, "/symphony-")
    end)
  end

  defp discover_preserved_files(source_root) do
    tmpl_dir = Path.join(source_root, "templates")

    if File.dir?(tmpl_dir) do
      walk_dir(tmpl_dir, "")
    else
      []
    end
  end

  defp walk_dir(dir, prefix) do
    case File.ls(dir) do
      {:ok, entries} ->
        Enum.flat_map(entries, fn entry ->
          full = Path.join(dir, entry)
          rel = if prefix == "", do: entry, else: Path.join(prefix, entry)

          if File.dir?(full) do
            walk_dir(full, rel)
          else
            [{rel, full}]
          end
        end)

      {:error, _} ->
        []
    end
  end

  defp rendered_dest(rel_path) do
    # Remove .symphony suffix: WORKFLOW.md.symphony -> WORKFLOW.md
    basename = Path.basename(rel_path)

    new_basename =
      case Path.extname(basename) do
        ".symphony" ->
          Path.rootname(basename)

        _ ->
          basename
      end

    dir = Path.dirname(rel_path)
    if dir == ".", do: new_basename, else: Path.join(dir, new_basename)
  end

  defp create_symlinks(target_dir) do
    symlinks = [
      {".claude", ".agents"},
      {".cursor", ".agents"},
      {".codex", ".agents"}
    ]

    Enum.each(symlinks, fn {link_name, target} ->
      link_path = Path.join(target_dir, link_name)
      target_path = Path.join(target_dir, target)

      cond do
        File.exists?(link_path) and not is_symlink?(link_path) ->
          # Real file/dir exists — skip
          :ok

        is_symlink?(link_path) ->
          # Already a symlink — check target
          current = File.read_link!(link_path)

          if current != target_path do
            File.rm!(link_path)
            File.ln_s!(target_path, link_path)
          end

        true ->
          File.ln_s!(target_path, link_path)
      end
    end)
  end

  defp is_symlink?(path) do
    case File.lstat(path) do
      {:ok, %File.Stat{type: :symlink}} -> true
      _ -> false
    end
  end

  defp default_source_root do
    # First try in-application priv (escript bundle), fall back to repo-level priv (dev)
    path = Application.app_dir(:symphony_elixir, "priv/agents")

    if File.dir?(path) do
      path
    else
      # Dev / test: read from repo root .agents/
      Path.join(File.cwd!(), "priv/agents")
    end
  end

  defp read_manifest(path) do
    if File.regular?(path) do
      case YamlElixir.read_from_file(path) do
        {:ok, map} when is_map(map) -> map
        _ -> nil
      end
    end
  end

  defp write_manifest(path, version, files) do
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    body =
      [
        ~s(symphony_version: "#{version}"),
        ~s(created_at: "#{now}"),
        ~s(last_upgraded_at: "#{now}"),
        "files:"
      ] ++
        Enum.map(files, fn {rel, %{"category" => cat}} ->
          "  #{rel}: {category: #{cat}}"
        end)

    File.write!(path, Enum.join(body, "\n") <> "\n")
  end
end
