defmodule SymphonyElixir.Tracker.GitHub.Client do
  @moduledoc """
  GitHub Issues client using `gh` CLI for issue reads.
  """

  require Logger
  alias SymphonyElixir.{Config, Linear.Issue}

  @issue_page_size 50

  @spec fetch_candidate_issues() :: {:ok, [Issue.t()]} | {:error, term()}
  def fetch_candidate_issues do
    tracker = Config.settings!().tracker

    if is_nil(tracker.repo) do
      {:error, :missing_github_repo}
    else
      active = MapSet.new(tracker.active_states |> Enum.map(&normalize_issue_state/1))

      case list_issues(tracker.repo, "open") do
        {:ok, issues} ->
          filtered =
            issues
            |> Enum.filter(fn issue ->
              MapSet.member?(active, normalize_issue_state(issue["state"]))
            end)
            |> Enum.map(&normalize_issue/1)

          {:ok, filtered}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @spec fetch_issues_by_states([String.t()]) :: {:ok, [Issue.t()]} | {:error, term()}
  def fetch_issues_by_states(state_names) when is_list(state_names) do
    normalized = Enum.map(state_names, &normalize_issue_state/1) |> Enum.uniq()

    if normalized == [] do
      {:ok, []}
    else
      tracker = Config.settings!().tracker

      if is_nil(tracker.repo) do
        {:error, :missing_github_repo}
      else
        gh_state = gh_list_state(normalized)
        wanted = MapSet.new(normalized)

        case list_issues(tracker.repo, gh_state) do
          {:ok, issues} ->
            filtered =
              issues
              |> Enum.filter(fn issue ->
                MapSet.member?(wanted, normalize_issue_state(issue["state"]))
              end)
              |> Enum.map(&normalize_issue/1)

            {:ok, filtered}

          {:error, reason} ->
            {:error, reason}
        end
      end
    end
  end

  @spec fetch_issue_states_by_ids([String.t()]) :: {:ok, [Issue.t()]} | {:error, term()}
  def fetch_issue_states_by_ids(issue_ids) when is_list(issue_ids) do
    ids = Enum.uniq(issue_ids)

    if ids == [] do
      {:ok, []}
    else
      tracker = Config.settings!().tracker

      if is_nil(tracker.repo) do
        {:error, :missing_github_repo}
      else
        wanted = MapSet.new(ids)

        case list_issues(tracker.repo, "all") do
          {:ok, issues} ->
            filtered =
              issues
              |> Enum.filter(fn issue ->
                number = issue["number"]
                is_integer(number) and MapSet.member?(wanted, Integer.to_string(number))
              end)
              |> Enum.map(&normalize_issue/1)

            {:ok, filtered}

          {:error, reason} ->
            {:error, reason}
        end
      end
    end
  end

  defp list_issues(repo, state) do
    args = ~w[issue list --repo #{repo} --state #{state} --json number,title,body,state,labels,url,createdAt,updatedAt,id --limit #{@issue_page_size}]

    case System.cmd("gh", args, stderr_to_stdout: true) do
      {output, 0} ->
        case Jason.decode(output) do
          {:ok, issues} when is_list(issues) -> {:ok, issues}
          {:ok, _} -> {:error, :github_unexpected_json}
          {:error, _} -> {:error, :github_json_decode}
        end

      {output, exit_code} ->
        Logger.error(
          "gh issue list failed repo=#{repo} state=#{state} exit=#{exit_code}: #{String.trim(output)}"
        )

        {:error, {:github_cli, exit_code, String.trim(output)}}
    end
  end

  defp gh_list_state(normalized) do
    has_open = "open" in normalized
    has_closed = "closed" in normalized

    cond do
      has_open and has_closed -> "all"
      has_open -> "open"
      has_closed -> "closed"
      true -> "all"
    end
  end

  defp normalize_issue_state(state) when is_binary(state) do
    state |> String.trim() |> String.downcase()
  end

  defp normalize_issue_state(_), do: ""

  defp normalize_issue(issue) when is_map(issue) do
    number = issue["number"]

    %Issue{
      id: to_string(number),
      identifier: "gh-#{number}",
      title: issue["title"] || "",
      description: issue["body"] || "",
      priority: nil,
      state: issue["state"] || "",
      branch_name: nil,
      url: issue["url"] || "",
      assignee_id: nil,
      labels: extract_labels(issue),
      assigned_to_worker: true,
      created_at: parse_datetime(issue["createdAt"]),
      updated_at: parse_datetime(issue["updatedAt"])
    }
  end

  defp normalize_issue(_), do: nil

  defp extract_labels(%{"labels" => labels}) when is_list(labels) do
    labels
    |> Enum.map(& &1["name"])
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&String.downcase/1)
  end

  defp extract_labels(_), do: []

  defp parse_datetime(nil), do: nil

  defp parse_datetime(raw) do
    case DateTime.from_iso8601(raw) do
      {:ok, dt, _offset} -> dt
      _ -> nil
    end
  end
end
