defmodule SymphonyElixirWeb.PresenterAggregatesTest do
  use ExUnit.Case, async: true

  alias SymphonyElixirWeb.Presenter

  test "global_agent_totals_from_project_states sums counts" do
    states = %{
      "a" => %{counts: %{running: 2, retrying: 1, completed: 3}},
      "b" => %{counts: %{running: 0, retrying: 0, completed: 10}}
    }

    assert Presenter.global_agent_totals_from_project_states(states) == %{
             running: 2,
             retrying: 1,
             completed: 13
           }
  end

  test "global_agent_totals_from_project_states skips entries without counts" do
    states = %{
      "a" => %{counts: %{running: 1, retrying: 0, completed: 0}},
      "b" => %{error: %{code: "x", message: "y"}}
    }

    assert Presenter.global_agent_totals_from_project_states(states) == %{
             running: 1,
             retrying: 0,
             completed: 0
           }
  end
end
