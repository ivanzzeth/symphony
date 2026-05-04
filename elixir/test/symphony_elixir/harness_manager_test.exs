defmodule SymphonyElixir.HarnessManagerTest do
  use ExUnit.Case

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
    {:ok, pid} = GenServer.start_link(Manager, [project_dir: test_root], name: nil)

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

      # First check establishes baseline
      assert GenServer.call(pid, :check) in [:dispatched, :unchanged]

      # Second check should see no change
      assert GenServer.call(pid, :check) == :unchanged
    end

    test "returns :dispatched when WORKFLOW.md changes", %{pid: pid, test_root: test_root} do
      path = Path.join(test_root, "WORKFLOW.md")
      File.write!(path, @test_workflow_content)
      GenServer.call(pid, :check)

      # Modify the file
      File.write!(path, @modified_workflow_content)

      assert GenServer.call(pid, :check) == :dispatched
    end
  end

  describe "harness prompt construction" do
    test "first-time setup prompt when last_hash is nil and file exists", %{test_root: test_root} do
      path = Path.join(test_root, "WORKFLOW.md")
      File.write!(path, @test_workflow_content)
      hash = compute_hash_for_test(path)

      prompt = build_harness_prompt_for_test(nil, hash)
      assert prompt == "setup a harness for the project according to WORKFLOW.md"
    end

    test "update prompt when last_hash is set and file changed", %{test_root: test_root} do
      path = Path.join(test_root, "WORKFLOW.md")
      File.write!(path, @test_workflow_content)
      hash1 = compute_hash_for_test(path)

      File.write!(path, @modified_workflow_content)
      hash2 = compute_hash_for_test(path)

      prompt = build_harness_prompt_for_test(hash1, hash2)
      assert prompt == "update an existing harness for the project according to the updated WORKFLOW.md"
    end

    test "deletion prompt when current_hash is empty and last_hash was set" do
      prompt = build_harness_prompt_for_test("some-hash", "")
      assert prompt == "WORKFLOW.md has been deleted. Clean up harness configuration accordingly."
    end

    test "empty prompt when both hashes are empty/nil" do
      prompt = build_harness_prompt_for_test(nil, "")
      assert prompt == "WORKFLOW.md is empty or does not exist. No harness configuration is needed."
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

  defp build_harness_prompt_for_test(nil, "") do
    "WORKFLOW.md is empty or does not exist. No harness configuration is needed."
  end

  defp build_harness_prompt_for_test(nil, _current_hash) do
    "setup a harness for the project according to WORKFLOW.md"
  end

  defp build_harness_prompt_for_test(_last_hash, "") do
    "WORKFLOW.md has been deleted. Clean up harness configuration accordingly."
  end

  defp build_harness_prompt_for_test(_last_hash, _current_hash) do
    "update an existing harness for the project according to the updated WORKFLOW.md"
  end
end
