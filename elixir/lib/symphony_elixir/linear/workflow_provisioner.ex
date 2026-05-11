defmodule SymphonyElixir.Linear.WorkflowProvisioner do
  @moduledoc """
  Ensures required workflow states exist in the Linear project on startup.

  Queries the team's current workflow states, compares against the desired
  states from WORKFLOW.md, and creates any missing states via the Linear API.

  Linear removed `Team.workflowStates` in favor of `Team.states` (paginated
  `WorkflowStateConnection`). Error hints may name `draftWorkflowState` and similar;
  in the current schema those are deprecated Git automation pointers (see
  `gitAutomationStates`), not a substitute for listing the whole board.
  """

  require Logger
  alias SymphonyElixir.{Config, Linear.Client}

  @team_query """
  query SymphonyTeamByProject($projectSlug: String!) {
    projects(filter: {slugId: {eq: $projectSlug}}, first: 1) {
      nodes {
        teams(first: 1) {
          nodes {
            id
            name
          }
        }
      }
    }
  }
  """

  # Paginated: teams can exceed one page of workflow states.
  @states_query """
  query SymphonyWorkflowStates($teamId: String!, $first: Int!, $after: String) {
    team(id: $teamId) {
      states(first: $first, after: $after) {
        nodes {
          id
          name
          type
          position
        }
        pageInfo {
          hasNextPage
          endCursor
        }
      }
    }
  }
  """

  @create_state_mutation """
  mutation SymphonyCreateWorkflowState($input: WorkflowStateCreateInput!) {
    workflowStateCreate(input: $input) {
      success
      workflowState {
        id
        name
        type
        position
      }
    }
  }
  """

  @state_colors %{
    "Backlog" => "#bec2c8",
    "Todo" => "#e2e2e2",
    "In Progress" => "#f2c94c",
    "In Review" => "#f2994a",
    "Merging" => "#5e6ad2",
    "Rework" => "#eb5757",
    "Done" => "#5dc97c",
    "Canceled" => "#95a2b3",
    "Duplicate" => "#95a2b3"
  }

  @type provision_result :: {:ok, [String.t()]} | {:error, term()}

  @doc """
  Ensures all required workflow states exist for the configured Linear project.

  Returns `{:ok, created_names}` with names of newly created states,
  or `{:ok, []}` if all states already existed.

  ## Options

  * `:request_fun` — forwarded to `SymphonyElixir.Linear.Client.graphql/3` (tests, tooling).
  """
  @spec provision() :: provision_result()
  @spec provision(keyword()) :: provision_result()
  def provision(opts \\ []) when is_list(opts) do
    gql_opts = Keyword.take(opts, [:request_fun])
    config = Config.settings!()

    with {:ok, team_id} <- resolve_team_id(config.tracker.project_slug, gql_opts),
         {:ok, existing_states} <- fetch_workflow_states(team_id, gql_opts) do
      desired = config.tracker.active_states ++ config.tracker.terminal_states
      existing_names = MapSet.new(existing_states, & &1["name"])
      missing = Enum.filter(desired, &(!MapSet.member?(existing_names, &1)))

      if missing == [] do
        Logger.info("All required Linear workflow states present")
        {:ok, []}
      else
        Logger.info("Missing Linear workflow states: #{inspect(missing)}; creating...")
        created = Enum.map(missing, &create_workflow_state(team_id, &1, existing_states, gql_opts))
        {:ok, Enum.filter(created, &(&1 != nil))}
      end
    end
  end

  defp resolve_team_id(project_slug, gql_opts) do
    with {:ok, response} <- Client.graphql(@team_query, %{projectSlug: project_slug}, gql_opts) do
      case get_in(response, ["data", "projects", "nodes", Access.at(0), "teams", "nodes", Access.at(0), "id"]) do
        team_id when is_binary(team_id) -> {:ok, team_id}
        _ -> {:error, :team_not_found}
      end
    end
  end

  @states_page_size 100

  defp fetch_workflow_states(team_id, gql_opts) do
    fetch_workflow_states(team_id, gql_opts, [], nil)
  end

  defp fetch_workflow_states(team_id, gql_opts, acc, after_cursor) do
    variables =
      %{teamId: team_id, first: @states_page_size, after: after_cursor}

    with {:ok, response} <- Client.graphql(@states_query, variables, gql_opts) do
      nodes = get_in(response, ["data", "team", "states", "nodes"]) || []
      page_info = get_in(response, ["data", "team", "states", "pageInfo"]) || %{}
      merged = acc ++ nodes

      case page_info do
        %{"hasNextPage" => true, "endCursor" => cursor} when is_binary(cursor) ->
          fetch_workflow_states(team_id, gql_opts, merged, cursor)

        _ ->
          {:ok, merged}
      end
    end
  end

  defp create_workflow_state(team_id, state_name, existing_states, gql_opts) do
    color = Map.get(@state_colors, state_name, "#95a2b3")

    # Position new states after the last existing state
    max_position =
      existing_states
      |> Enum.map(&Map.get(&1, "position", 0))
      |> Enum.max(fn -> 0 end)

    position = max_position + 0.5

    input = %{
      teamId: team_id,
      name: state_name,
      type: "started",
      color: color,
      position: position
    }

    case Client.graphql(@create_state_mutation, %{input: input}, gql_opts) do
      {:ok, %{"data" => %{"workflowStateCreate" => %{"success" => true}}}} ->
        Logger.info("Created Linear workflow state: #{state_name} (position=#{position})")
        state_name

      {:ok, %{"data" => %{"workflowStateCreate" => %{"success" => false}}}} ->
        Logger.warning("Failed to create Linear workflow state: #{state_name}")
        nil

      {:error, reason} ->
        Logger.warning("Failed to create Linear workflow state #{state_name}: #{inspect(reason)}")
        nil
    end
  end
end
