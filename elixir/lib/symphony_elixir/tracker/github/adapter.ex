defmodule SymphonyElixir.Tracker.GitHub.Adapter do
  @moduledoc """
  GitHub Issues-backed tracker adapter using `gh` CLI for reads and writes.
  """

  @behaviour SymphonyElixir.Tracker

  alias SymphonyElixir.Config
  alias SymphonyElixir.Tracker.GitHub.Client

  @spec fetch_candidate_issues() :: {:ok, [term()]} | {:error, term()}
  def fetch_candidate_issues, do: Client.fetch_candidate_issues()

  @spec fetch_issues_by_states([String.t()]) :: {:ok, [term()]} | {:error, term()}
  def fetch_issues_by_states(states), do: Client.fetch_issues_by_states(states)

  @spec fetch_issue_states_by_ids([String.t()]) :: {:ok, [term()]} | {:error, term()}
  def fetch_issue_states_by_ids(issue_ids), do: Client.fetch_issue_states_by_ids(issue_ids)

  @spec fetch_issue_by_identifier(String.t(), keyword()) :: {:ok, term()} | {:error, term()}
  def fetch_issue_by_identifier(identifier, opts \\ []) when is_binary(identifier) and is_list(opts) do
    Client.fetch_issue_by_identifier(identifier, opts)
  end

  @spec create_comment(String.t(), String.t()) :: :ok | {:error, term()}
  def create_comment(issue_id, body) when is_binary(issue_id) and is_binary(body) do
    with {:ok, repo} <- tracker_repo() do
      args = ["issue", "comment", issue_id, "--repo", repo, "--body", body]

      case System.cmd("gh", args, stderr_to_stdout: true) do
        {_, 0} -> :ok
        {output, exit_code} -> {:error, {:github_cli, exit_code, String.trim(output)}}
      end
    end
  end

  @spec update_issue_state(String.t(), String.t()) :: :ok | {:error, term()}
  def update_issue_state(issue_id, state_name)
      when is_binary(issue_id) and is_binary(state_name) do
    with {:ok, repo} <- tracker_repo() do
      action = normalize_action(state_name)
      args = ["issue", action, issue_id, "--repo", repo]

      case System.cmd("gh", args, stderr_to_stdout: true) do
        {_, 0} -> :ok
        {output, exit_code} -> {:error, {:github_cli, exit_code, String.trim(output)}}
      end
    end
  end

  defp tracker_repo do
    case Config.settings!().tracker.repo do
      repo when is_binary(repo) and repo != "" -> {:ok, repo}
      _ -> {:error, :missing_github_repo}
    end
  end

  defp normalize_action(state_name) when is_binary(state_name) do
    normalized = state_name |> String.trim() |> String.downcase()

    case normalized do
      "closed" -> "close"
      _ -> "reopen"
    end
  end
end
