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

  @spec create_comment(String.t(), String.t()) :: :ok | {:error, term()}
  def create_comment(issue_id, body) when is_binary(issue_id) and is_binary(body) do
    repo = Config.settings!().tracker.repo

    if is_nil(repo) do
      {:error, :missing_github_repo}
    else
      args = ~w[issue comment #{issue_id} --repo #{repo} --body #{body}]

      case System.cmd("gh", args, stderr_to_stdout: true) do
        {_, 0} -> :ok
        {output, exit_code} -> {:error, {:github_cli, exit_code, String.trim(output)}}
      end
    end
  end

  @spec update_issue_state(String.t(), String.t()) :: :ok | {:error, term()}
  def update_issue_state(issue_id, state_name)
      when is_binary(issue_id) and is_binary(state_name) do
    repo = Config.settings!().tracker.repo

    if is_nil(repo) do
      {:error, :missing_github_repo}
    else
      action = normalize_action(state_name)
      args = ~w[issue #{action} #{issue_id} --repo #{repo}]

      case System.cmd("gh", args, stderr_to_stdout: true) do
        {_, 0} -> :ok
        {output, exit_code} -> {:error, {:github_cli, exit_code, String.trim(output)}}
      end
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
