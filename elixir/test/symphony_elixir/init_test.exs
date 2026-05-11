defmodule SymphonyElixir.InitTest do
  use ExUnit.Case, async: false

  alias SymphonyElixir.Init

  setup do
    dir =
      Path.join(
        System.tmp_dir!(),
        "symphony-init-test-#{System.unique_integer([:positive])}"
      )

    # Create a minimal source structure (simulates embedded templates)
    source = Path.join(dir, "source")
    skills_dir = Path.join(source, "skills")
    agents_dir = Path.join(source, "agents")
    templates_dir = Path.join(source, "templates")
    File.mkdir_p!(skills_dir)
    File.mkdir_p!(agents_dir)
    File.mkdir_p!(templates_dir)

    # Create a managed skill file
    linear_dir = Path.join(skills_dir, "symphony-linear")
    File.mkdir_p!(linear_dir)
    File.write!(Path.join(linear_dir, "SKILL.md"), "# symphony-linear\nGeneric Linear skill.")

    pull_dir = Path.join(skills_dir, "symphony-pull")
    File.mkdir_p!(pull_dir)
    File.write!(Path.join(pull_dir, "SKILL.md"), "# symphony-pull\nGeneric pull skill.")

    planner = Path.join(agents_dir, "symphony-planner.md")
    File.write!(planner, "# symphony-planner\nGeneric planner.")

    # Create template files
    File.write!(Path.join(templates_dir, "WORKFLOW.md.symphony"), "workflow {{base_branch}}")
    File.write!(Path.join(templates_dir, "AGENTS.md.symphony"), "agents {{project_name}}")

    # vars file
    File.write!(Path.join(source, "symphony-vars.yaml"), "base_branch: {{base_branch}}")

    on_exit(fn -> File.rm_rf(dir) end)

    %{tmp: dir, source: source}
  end

  describe "init/1" do
    test "creates expected directory structure in target", %{tmp: tmp, source: source} do
      target = Path.join(tmp, "target")
      assert :ok = Init.run(target_dir: target, source_root: source)

      assert File.dir?(Path.join(target, ".agents"))
      assert File.dir?(Path.join([target, ".agents", "skills"]))
      assert File.dir?(Path.join([target, ".agents", "agents"]))
      assert File.dir?(Path.join([target, ".agents", "templates"]))
    end

    test "copies managed skill files from source to target", %{tmp: tmp, source: source} do
      target = Path.join(tmp, "target")
      assert :ok = Init.run(target_dir: target, source_root: source)

      assert File.regular?(Path.join([target, ".agents", "skills", "symphony-linear", "SKILL.md"]))
      assert File.regular?(Path.join([target, ".agents", "skills", "symphony-pull", "SKILL.md"]))
      assert File.regular?(Path.join([target, ".agents", "agents", "symphony-planner.md"]))

      content = File.read!(Path.join([target, ".agents", "skills", "symphony-linear", "SKILL.md"]))
      assert content =~ "symphony-linear"
    end

    test "renders template files from templates to target root", %{tmp: tmp, source: source} do
      target = Path.join(tmp, "target")
      assert :ok = Init.run(target_dir: target, source_root: source)

      assert File.regular?(Path.join(target, "WORKFLOW.md"))
      assert File.regular?(Path.join(target, "AGENTS.md"))
      assert File.regular?(Path.join([target, ".agents", "symphony-vars.yaml"]))

      wf_content = File.read!(Path.join(target, "WORKFLOW.md"))
      assert wf_content =~ "workflow {{base_branch}}"
    end

    test "creates .symphony-manifest.yaml with file categories", %{tmp: tmp, source: source} do
      target = Path.join(tmp, "target")
      assert :ok = Init.run(target_dir: target, source_root: source)

      manifest = Path.join([target, ".agents", ".symphony-manifest.yaml"])
      assert File.regular?(manifest)

      content = YamlElixir.read_from_file!(manifest)
      assert content["symphony_version"] |> is_binary()
      assert content["files"] |> is_map()

      files = content["files"]
      # managed files
      assert files["skills/symphony-linear/SKILL.md"]["category"] == "managed"
      assert files["agents/symphony-planner.md"]["category"] == "managed"
      # preserved files
      assert files["WORKFLOW.md"]["category"] == "preserved"
      assert files[".agents/symphony-vars.yaml"]["category"] == "preserved"
    end

    test "fails when .agents already exists without --upgrade", %{tmp: tmp, source: source} do
      target = Path.join(tmp, "target")
      File.mkdir_p!(Path.join(target, ".agents"))

      assert {:error, msg} = Init.run(target_dir: target, source_root: source)
      assert msg =~ "already exists"
      assert msg =~ "--upgrade"
    end

    test "with --upgrade overwrites managed files but preserves preserved files",
         %{tmp: tmp, source: source} do
      target = Path.join(tmp, "target")

      # First init
      assert :ok = Init.run(target_dir: target, source_root: source)

      # Modify a preserved file to simulate user customization
      wf_path = Path.join(target, "WORKFLOW.md")
      File.write!(wf_path, "USER CUSTOMIZED WORKFLOW")

      # Modify a managed file to simulate user changing it
      skill_path = Path.join([target, ".agents", "skills", "symphony-linear", "SKILL.md"])
      File.write!(skill_path, "USER MODIFIED")

      # Upgrade
      assert :ok = Init.run(target_dir: target, source_root: source, upgrade: true)

      # Preserved should remain as user left it
      assert File.read!(wf_path) =~ "USER CUSTOMIZED WORKFLOW"

      # Managed should be overwritten
      assert File.read!(skill_path) =~ "symphony-linear"
    end

    test "with --force overwrites preserved files too", %{tmp: tmp, source: source} do
      target = Path.join(tmp, "target")

      assert :ok = Init.run(target_dir: target, source_root: source)

      wf_path = Path.join(target, "WORKFLOW.md")
      File.write!(wf_path, "USER CUSTOMIZED WORKFLOW")

      assert :ok = Init.run(target_dir: target, source_root: source, force: true)

      # Preserved should be overwritten
      assert File.read!(wf_path) =~ "workflow {{base_branch}}"
    end

    test "with --upgrade creates newly added managed files", %{tmp: tmp, source: source} do
      target = Path.join(tmp, "target")

      # First init
      assert :ok = Init.run(target_dir: target, source_root: source)

      # Add a new skill to source
      File.mkdir_p!(Path.join([source, "skills", "symphony-commit"]))
      File.write!(Path.join([source, "skills", "symphony-commit", "SKILL.md"]), "# symphony-commit")

      # Upgrade
      assert :ok = Init.run(target_dir: target, source_root: source, upgrade: true)

      assert File.regular?(
               Path.join([target, ".agents", "skills", "symphony-commit", "SKILL.md"])
             )
    end
  end
end
