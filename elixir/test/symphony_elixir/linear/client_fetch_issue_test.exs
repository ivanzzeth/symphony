defmodule SymphonyElixir.Linear.ClientFetchIssueTest do
  use SymphonyElixir.TestSupport, async: false

  alias SymphonyElixir.Linear.Client

  test "fetch_issue_by_identifier resolves human-readable identifier via issues filter (stubbed HTTP)" do
    issue_node = %{
      "id" => "550e8400-e29b-41d4-a716-446655440000",
      "identifier" => "WEB-81",
      "title" => "Example",
      "description" => "d",
      "priority" => 1,
      "state" => %{"name" => "Todo"},
      "branchName" => "b",
      "url" => "https://example.com",
      "assignee" => nil,
      "labels" => %{"nodes" => []},
      "inverseRelations" => %{"nodes" => []},
      "createdAt" => "2026-01-01T00:00:00.000Z",
      "updatedAt" => "2026-01-01T00:00:00.000Z"
    }

    request_fun = fn _payload, _headers ->
      body = %{"data" => %{"issues" => %{"nodes" => [issue_node]}}}
      {:ok, %{status: 200, body: body}}
    end

    assert {:ok, issue} = Client.fetch_issue_by_identifier("WEB-81", request_fun: request_fun)
    assert issue.identifier == "WEB-81"
    assert issue.id == "550e8400-e29b-41d4-a716-446655440000"
  end

  test "fetch_issue_by_identifier returns not_found when GraphQL returns empty nodes (stubbed HTTP)" do
    request_fun = fn _payload, _headers ->
      {:ok, %{status: 200, body: %{"data" => %{"issues" => %{"nodes" => []}}}}}
    end

    assert {:error, :not_found} = Client.fetch_issue_by_identifier("MISSING", request_fun: request_fun)
  end
end
