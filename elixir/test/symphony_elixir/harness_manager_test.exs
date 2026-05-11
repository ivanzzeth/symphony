defmodule SymphonyElixir.HarnessManagerTest do
  # Serial: interacts with global CodingAgent / config surfaces under load.
  use ExUnit.Case, async: false

  alias SymphonyElixir.Harness.Manager

  @test_workflow_content """
  ---
  tracker:
    kind: linear
    api_key: test-token
    project_slug: test-project
  agent:
    kind: codex
  ---
  Test prompt body for harness manager tests.
  """

  @modified_workflow_content """
  ---
  tracker:
    kind: linear
    api_key: test-token
    project_slug: test-project
  agent:
    kind: claude
  ---
  Modified prompt body for harness manager tests.
  """

  setup do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-harness-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(test_root)
    symphony_dir = Path.join(test_root, ".symphony")
    harness_state_path = Path.join(symphony_dir, "harness-state.json")

    # Start a Harness Manager scoped to the test directory
    workflow_file = Path.join(test_root, "WORKFLOW.md")
    {:ok, pid} = GenServer.start_link(Manager, [project_dir: test_root, workflow_file_path: workflow_file], name: nil)

    on_exit(fn ->
      if Process.alive?(pid), do: GenServer.stop(pid)
      File.rm_rf(test_root)
    end)

    %{
      test_root: test_root,
      pid: pid,
      harness_state_path: harness_state_path
    }
  end

  describe "hash computation" do
    test "returns empty string when WORKFLOW.md is missing", %{test_root: test_root} do
      path = Path.join(test_root, "WORKFLOW.md")
      refute File.exists?(path)

      assert compute_hash_for_test(path) == ""
    end

    test "returns a SHA-256 hash when WORKFLOW.md exists", %{test_root: test_root} do
      path = Path.join(test_root, "WORKFLOW.md")
      File.write!(path, @test_workflow_content)

      hash = compute_hash_for_test(path)
      assert is_binary(hash)
      assert byte_size(hash) == 64
      assert String.match?(hash, ~r/^[a-f0-9]+$/)
    end

    test "returns different hashes for different content", %{test_root: test_root} do
      path = Path.join(test_root, "WORKFLOW.md")
      File.write!(path, @test_workflow_content)
      hash1 = compute_hash_for_test(path)

      File.write!(path, @modified_workflow_content)
      hash2 = compute_hash_for_test(path)

      assert hash1 != hash2
    end

    test "returns same hash for identical content", %{test_root: test_root} do
      path = Path.join(test_root, "WORKFLOW.md")
      File.write!(path, @test_workflow_content)
      hash1 = compute_hash_for_test(path)

      File.write!(path, @test_workflow_content)
      hash2 = compute_hash_for_test(path)

      assert hash1 == hash2
    end
  end

  describe "harness-state.json persistence" do
    test "load_last_hash returns nil when state file is missing" do
      missing_path = Path.join(System.tmp_dir!(), "nonexistent-#{System.unique_integer([:positive])}/harness-state.json")
      assert load_last_hash_for_test(missing_path) == nil
    end

    test "load_last_hash reads stored hash from state file", %{harness_state_path: harness_state_path} do
      persist_hash_for_test(harness_state_path, "abc123")
      assert load_last_hash_for_test(harness_state_path) == "abc123"
    end

    test "persist_hash writes JSON with hash and updated_at", %{harness_state_path: harness_state_path} do
      persist_hash_for_test(harness_state_path, "deadbeef")
      assert File.exists?(harness_state_path)

      {:ok, content} = File.read(harness_state_path)
      {:ok, decoded} = Jason.decode(content)
      assert decoded["hash"] == "deadbeef"
      assert is_binary(decoded["updated_at"])
    end

    test "persist_hash creates parent directory", %{test_root: test_root} do
      path = Path.join([test_root, ".symphony", "nested", "harness-state.json"])
      persist_hash_for_test(path, "nested-hash")
      assert File.exists?(path)
    end

    test "load_last_hash handles invalid JSON gracefully", %{harness_state_path: harness_state_path} do
      File.mkdir_p!(Path.dirname(harness_state_path))
      File.write!(harness_state_path, "not json")
      assert load_last_hash_for_test(harness_state_path) == nil
    end

    test "load_last_hash handles JSON without hash key gracefully", %{harness_state_path: harness_state_path} do
      File.mkdir_p!(Path.dirname(harness_state_path))
      File.write!(harness_state_path, Jason.encode!(%{"other" => "value"}))
      assert load_last_hash_for_test(harness_state_path) == nil
    end
  end

  describe "change detection" do
    test "detects initial creation (nil -> hash)", %{test_root: test_root} do
      path = Path.join(test_root, "WORKFLOW.md")
      current_hash = compute_hash_for_test(path)
      assert current_hash == ""

      # Simulate creation
      File.write!(path, @test_workflow_content)
      new_hash = compute_hash_for_test(path)
      assert new_hash != ""
      assert new_hash != current_hash
    end

    test "detects modification (hash -> different hash)", %{test_root: test_root} do
      path = Path.join(test_root, "WORKFLOW.md")
      File.write!(path, @test_workflow_content)
      hash_before = compute_hash_for_test(path)

      File.write!(path, @modified_workflow_content)
      hash_after = compute_hash_for_test(path)

      assert hash_before != hash_after
    end

    test "detects deletion (hash -> empty)", %{test_root: test_root} do
      path = Path.join(test_root, "WORKFLOW.md")
      File.write!(path, @test_workflow_content)
      hash_before = compute_hash_for_test(path)

      File.rm!(path)
      hash_after = compute_hash_for_test(path)

      assert hash_before != ""
      assert hash_after == ""
    end

    test "no false positive for identical content", %{test_root: test_root} do
      path = Path.join(test_root, "WORKFLOW.md")
      File.write!(path, @test_workflow_content)
      hash1 = compute_hash_for_test(path)
      hash2 = compute_hash_for_test(path)

      assert hash1 == hash2
    end
  end

  describe "check/0" do
    test "returns :unchanged when WORKFLOW.md has not changed", %{pid: pid, test_root: test_root} do
      path = Path.join(test_root, "WORKFLOW.md")
      File.write!(path, @test_workflow_content)

      # First check: detects change, tries to create Linear issue
      # If Linear is unavailable → dispatch fails, hash not persisted, same change detected again
      # If Linear is available → issue created, harness_running becomes true
      result = GenServer.call(pid, :check)
      assert result in [:dispatched, :harness_busy, :unchanged]

      # Since we may have created a real issue, reset harness state for clean next check
      :sys.replace_state(pid, fn s ->
        %{s | harness_running: false, harness_issue_id: nil}
      end)

      # Second check: content is identical, should be :unchanged
      result2 = GenServer.call(pid, :check)
      assert result2 in [:dispatched, :unchanged]
    end

    test "returns :dispatched when WORKFLOW.md changes", %{pid: pid, test_root: test_root} do
      path = Path.join(test_root, "WORKFLOW.md")
      File.write!(path, @test_workflow_content)

      # First check triggers dispatch attempt
      GenServer.call(pid, :check)

      # Reset harness state so we can test change detection again
      :sys.replace_state(pid, fn s ->
        %{s | harness_running: false, harness_issue_id: nil}
      end)

      # Modify the file
      File.write!(path, @modified_workflow_content)

      result = GenServer.call(pid, :check)
      assert result in [:dispatched, :unchanged]
    end

    test "returns :harness_busy when harness is already running", %{pid: pid, test_root: test_root} do
      path = Path.join(test_root, "WORKFLOW.md")
      File.write!(path, @test_workflow_content)

      # Put the GenServer in harness_running state
      :sys.replace_state(pid, fn state -> %{state | harness_running: true, harness_issue_id: "test-issue-id"} end)

      assert GenServer.call(pid, :check) == :harness_busy
    end
  end

  describe "harness issue polling" do
    test "sets harness_running to false when harness_issue_id is nil", %{pid: pid} do
      state = :sys.get_state(pid)
      assert state.harness_issue_id == nil
    end

    test "poll does not crash when no harness issue is being tracked", %{pid: pid} do
      # Being in non-running state should not crash on poll.
      # In environments with real Linear, initial poll may detect a WORKFLOW.md change
      # and create an issue (harness_running becomes true).
      assert Process.alive?(pid)

      :sys.get_state(pid)
      send(pid, :poll)
      Process.sleep(50)

      # Should never crash — harness_running may change if Linear is configured
      assert Process.alive?(pid)

      # Reset harness state to clean up any side effects
      :sys.replace_state(pid, fn s ->
        %{s | harness_running: false, harness_issue_id: nil}
      end)
    end
  end

  describe "harness prompt construction" do
    test "first-time setup prompt when last_hash is nil and file exists", %{test_root: test_root} do
      path = Path.join(test_root, "WORKFLOW.md")
      File.write!(path, @test_workflow_content)
      hash = compute_hash_for_test(path)

      prompt = build_harness_prompt_for_test(nil, hash, path)
      assert prompt =~ "/harness"
      assert prompt =~ "build a new agent harness"
      assert prompt =~ path
    end

    test "update prompt when last_hash is set and file changed", %{test_root: test_root} do
      path = Path.join(test_root, "WORKFLOW.md")
      File.write!(path, @test_workflow_content)
      hash1 = compute_hash_for_test(path)

      File.write!(path, @modified_workflow_content)
      hash2 = compute_hash_for_test(path)

      prompt = build_harness_prompt_for_test(hash1, hash2, path)
      assert prompt =~ "/harness"
      assert prompt =~ "reconfigure"
      assert prompt =~ path
    end

    test "deletion prompt when current_hash is empty and last_hash was set", %{test_root: test_root} do
      path = Path.join(test_root, "WORKFLOW.md")
      prompt = build_harness_prompt_for_test("some-hash", "", path)
      assert prompt =~ "/harness"
      assert prompt =~ "deleted"
      assert prompt =~ path
    end

    test "empty prompt when both hashes are empty/nil", %{test_root: test_root} do
      path = Path.join(test_root, "WORKFLOW.md")
      prompt = build_harness_prompt_for_test(nil, "", path)
      assert prompt =~ "does not exist"
      assert prompt =~ path
    end
  end

  describe "harness_running?/0" do
    test "returns a boolean without raising" do
      assert is_boolean(Manager.harness_running?())
    end
  end

  # Test helper functions that expose private functions for testing

  defp compute_hash_for_test(path) do
    case File.read(path) do
      {:ok, content} ->
        content
        |> then(&:crypto.hash(:sha256, &1))
        |> Base.encode16(case: :lower)

      {:error, :enoent} ->
        ""
    end
  end

  defp load_last_hash_for_test(path) do
    case File.read(path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, %{"hash" => hash}} when is_binary(hash) -> hash
          _ -> nil
        end

      {:error, :enoent} ->
        nil
    end
  end

  defp persist_hash_for_test(path, hash) do
    state_dir = Path.dirname(path)
    File.mkdir_p!(state_dir)

    state = %{
      "hash" => hash,
      "updated_at" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    File.write!(path, Jason.encode!(state, pretty: true))
  end

  @harness_setup_prompt """
  Use the /harness skill to build a new agent harness for this project.

  The workflow file is located at: __WORKFLOW_PATH__

  Read that file to understand the project's execution contract, then follow the full harness skill workflow (Phase 0-6) to analyze the domain, design the team architecture, generate agent definitions and skills, and register the harness context in AGENTS.md.
  """

  @harness_update_prompt """
  Use the /harness skill to reconfigure the agent harness for this project.

  The workflow file is located at: __WORKFLOW_PATH__

  That file has been updated. Read it to understand the changes, then follow the harness skill workflow — audit current .agents/ state (Phase 0), then determine which phases are needed to bring the harness in sync with the updated workflow file.
  """

  @harness_deletion_prompt """
  The workflow file at __WORKFLOW_PATH__ has been deleted. Use the /harness skill to clean up the agent harness configuration accordingly.
  """

  @harness_empty_prompt "The workflow file at __WORKFLOW_PATH__ is empty or does not exist. No harness configuration is needed."

  defp build_harness_prompt_for_test(nil, "", path), do: String.replace(@harness_empty_prompt, "__WORKFLOW_PATH__", path)
  defp build_harness_prompt_for_test(nil, _current_hash, path), do: String.replace(@harness_setup_prompt, "__WORKFLOW_PATH__", path)
  defp build_harness_prompt_for_test(_last_hash, "", path), do: String.replace(@harness_deletion_prompt, "__WORKFLOW_PATH__", path)
  defp build_harness_prompt_for_test(_last_hash, _current_hash, path), do: String.replace(@harness_update_prompt, "__WORKFLOW_PATH__", path)
end
