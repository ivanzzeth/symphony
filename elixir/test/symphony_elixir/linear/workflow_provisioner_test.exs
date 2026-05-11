defmodule SymphonyElixir.Linear.WorkflowProvisionerTest do
  use SymphonyElixir.TestSupport, async: false

  alias SymphonyElixir.Linear.WorkflowProvisioner

  defp workflow_state(id, name, position) do
    %{
      "id" => id,
      "name" => name,
      "type" => "started",
      "position" => position
    }
  end

  defp desired_state_names do
    settings = SymphonyElixir.Config.settings!()
    settings.tracker.active_states ++ settings.tracker.terminal_states
  end

  test "provision uses Team.states path and succeeds when every desired state exists (stubbed HTTP)" do
    names = desired_state_names()
    states = Enum.with_index(names, 1) |> Enum.map(fn {n, i} -> workflow_state("id-#{i}", n, i * 1.0) end)

    request_fun = fn %{"query" => q} = payload, _headers ->
      cond do
        String.contains?(q, "SymphonyTeamByProject") ->
          body = %{
            "data" => %{
              "projects" => %{
                "nodes" => [
                  %{
                    "teams" => %{
                      "nodes" => [%{"id" => "team-stub", "name" => "Team"}]
                    }
                  }
                ]
              }
            }
          }

          {:ok, %{status: 200, body: body}}

        String.contains?(q, "SymphonyWorkflowStates") ->
          vars = Map.get(payload, "variables", %{})
          assert vars[:teamId] == "team-stub"
          assert vars[:first] == 100

          body = %{
            "data" => %{
              "team" => %{
                "states" => %{
                  "nodes" => states,
                  "pageInfo" => %{"hasNextPage" => false, "endCursor" => nil}
                }
              }
            }
          }

          {:ok, %{status: 200, body: body}}

        true ->
          flunk("unexpected GraphQL query in stub: #{inspect(String.slice(q, 0, 80))}")
      end
    end

    assert {:ok, []} = WorkflowProvisioner.provision(request_fun: request_fun)
  end

  test "provision follows states pagination until hasNextPage is false (stubbed HTTP)" do
    names = desired_state_names()
    assert length(names) >= 2

    [first_name | rest_names] = names
    page1 = [workflow_state("a", first_name, 1.0)]
    page2 = Enum.with_index(rest_names, 2) |> Enum.map(fn {n, i} -> workflow_state("p2-#{i}", n, i * 1.0) end)

    request_fun = fn %{"query" => q} = payload, _headers ->
      cond do
        String.contains?(q, "SymphonyTeamByProject") ->
          {:ok,
           %{
             status: 200,
             body: %{
               "data" => %{
                 "projects" => %{
                   "nodes" => [%{"teams" => %{"nodes" => [%{"id" => "team-page", "name" => "T"}]}}]
                 }
               }
             }
           }}

        String.contains?(q, "SymphonyWorkflowStates") ->
          vars = Map.get(payload, "variables", %{})
          after_cursor = vars[:after]

          body =
            if after_cursor == nil do
              %{
                "data" => %{
                  "team" => %{
                    "states" => %{
                      "nodes" => page1,
                      "pageInfo" => %{"hasNextPage" => true, "endCursor" => "c1"}
                    }
                  }
                }
              }
            else
              assert after_cursor == "c1"

              %{
                "data" => %{
                  "team" => %{
                    "states" => %{
                      "nodes" => page2,
                      "pageInfo" => %{"hasNextPage" => false, "endCursor" => nil}
                    }
                  }
                }
              }
            end

          {:ok, %{status: 200, body: body}}

        true ->
          flunk("unexpected GraphQL query in stub")
      end
    end

    assert {:ok, []} = WorkflowProvisioner.provision(request_fun: request_fun)
  end

  test "provision creates missing workflow states via workflowStateCreate (stubbed HTTP)" do
    names = desired_state_names()
    existing = Enum.drop(names, 2) |> Enum.with_index(1) |> Enum.map(fn {n, i} -> workflow_state("ex-#{i}", n, i * 1.0) end)
    missing_pair = Enum.take(names, 2)

    request_fun = fn %{"query" => q} = payload, _headers ->
      cond do
        String.contains?(q, "SymphonyTeamByProject") ->
          {:ok,
           %{
             status: 200,
             body: %{
               "data" => %{
                 "projects" => %{
                   "nodes" => [%{"teams" => %{"nodes" => [%{"id" => "team-create", "name" => "T"}]}}]
                 }
               }
             }
           }}

        String.contains?(q, "SymphonyWorkflowStates") ->
          {:ok,
           %{
             status: 200,
             body: %{
               "data" => %{
                 "team" => %{
                   "states" => %{
                     "nodes" => existing,
                     "pageInfo" => %{"hasNextPage" => false, "endCursor" => nil}
                   }
                 }
               }
             }
           }}

        String.contains?(q, "SymphonyCreateWorkflowState") ->
          vars = Map.get(payload, "variables", %{})
          input = Map.get(vars, :input) || Map.get(vars, "input")

          name =
            case input do
              %{"name" => n} -> n
              %{name: n} -> n
            end

          assert name in missing_pair

          {:ok,
           %{
             status: 200,
             body: %{"data" => %{"workflowStateCreate" => %{"success" => true}}}
           }}

        true ->
          flunk("unexpected GraphQL query in stub")
      end
    end

    assert {:ok, created} = WorkflowProvisioner.provision(request_fun: request_fun)
    assert Enum.sort(created) == Enum.sort(missing_pair)
  end
end
