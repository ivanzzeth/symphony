defmodule SymphonyElixir.Config.SchemaSymphonyProjectsTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Config.Schema

  test "absent projects key yields empty list" do
    assert {:ok, []} = Schema.parse_symphony_projects(%{})
    assert {:ok, []} = Schema.parse_symphony_projects(%{"server" => %{"port" => 4000}})
  end

  test "empty projects map yields empty list" do
    assert {:ok, []} = Schema.parse_symphony_projects(%{"projects" => %{}})
  end

  test "projects must be a mapping" do
    assert {:error, msg} = Schema.parse_symphony_projects(%{"projects" => []})
    assert msg =~ "mapping"
  end

  test "reject empty project_id key" do
    yaml = %{"projects" => %{"" => %{"workflow" => "/x"}}}

    assert {:error, msg} = Schema.parse_symphony_projects(yaml)
    assert msg =~ "empty project_id"
  end
end
