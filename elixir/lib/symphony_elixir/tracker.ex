defmodule SymphonyElixir.Tracker do
  @moduledoc """
  Adapter boundary for issue tracker reads and writes.
  """

  alias SymphonyElixir.Config

  @callback fetch_candidate_issues() :: {:ok, [term()]} | {:error, term()}
  @callback fetch_issues_by_states([String.t()]) :: {:ok, [term()]} | {:error, term()}
  @callback fetch_issue_states_by_ids([String.t()]) :: {:ok, [term()]} | {:error, term()}
  @callback create_comment(String.t(), String.t()) :: :ok | {:error, term()}
  @callback update_issue_state(String.t(), String.t()) :: :ok | {:error, term()}

  @spec fetch_candidate_issues(keyword()) :: {:ok, [term()]} | {:error, term()}
  def fetch_candidate_issues(opts \\ []) when is_list(opts) do
    adapter(opts).fetch_candidate_issues()
  end

  @spec fetch_issues_by_states([String.t()], keyword()) :: {:ok, [term()]} | {:error, term()}
  def fetch_issues_by_states(states, opts \\ []) when is_list(states) and is_list(opts) do
    adapter(opts).fetch_issues_by_states(states)
  end

  @spec fetch_issue_states_by_ids([String.t()], keyword()) :: {:ok, [term()]} | {:error, term()}
  def fetch_issue_states_by_ids(issue_ids, opts \\ []) when is_list(issue_ids) and is_list(opts) do
    adapter(opts).fetch_issue_states_by_ids(issue_ids)
  end

  @spec create_comment(String.t(), String.t(), keyword()) :: :ok | {:error, term()}
  def create_comment(issue_id, body, opts \\ []) when is_list(opts) do
    adapter(opts).create_comment(issue_id, body)
  end

  @spec update_issue_state(String.t(), String.t(), keyword()) :: :ok | {:error, term()}
  def update_issue_state(issue_id, state_name, opts \\ []) when is_list(opts) do
    adapter(opts).update_issue_state(issue_id, state_name)
  end

  @spec adapter(keyword()) :: module()
  def adapter(opts \\ []) when is_list(opts) do
    settings_opts =
      case Keyword.get(opts, :workflow_store) do
        nil -> []
        ws -> [workflow_store: ws]
      end

    case Config.settings!(settings_opts).tracker.kind do
      "memory" -> SymphonyElixir.Tracker.Memory
      "github" -> SymphonyElixir.Tracker.GitHub.Adapter
      _ -> SymphonyElixir.Linear.Adapter
    end
  end
end
