defmodule SymphonyElixir.PromptBuilder do
  @moduledoc """
  Builds agent prompts from Linear issue data.
  """

  alias SymphonyElixir.{Config, Rescue, Workflow, WorkflowStore}

  @render_opts [strict_variables: true, strict_filters: true]

  @spec build_prompt(SymphonyElixir.Linear.Issue.t(), keyword()) :: String.t()
  def build_prompt(issue, opts \\ []) do
    ws = Keyword.get(opts, :workflow_store)

    wf_result =
      case ws do
        nil -> Workflow.current()
        store -> WorkflowStore.current(store)
      end

    template =
      wf_result
      |> prompt_template!(ws)
      |> parse_template!()

    template
    |> Solid.render!(
      %{
        "attempt" => Keyword.get(opts, :attempt),
        "issue" => issue |> Map.from_struct() |> to_solid_map(),
        "workspace" => workspace_template_vars(ws),
        "tracker" => tracker_template_vars(ws)
      },
      @render_opts
    )
    |> IO.iodata_to_binary()
  end

  defp workspace_template_vars(ws) do
    cfg = Config.settings!(workflow_store: ws)
    %{"root" => cfg.workspace.root, "base_branch" => cfg.workspace.base_branch}
  end

  defp tracker_template_vars(ws) do
    t = Config.settings!(workflow_store: ws).tracker
    %{"repo" => t.repo}
  end

  defp prompt_template!({:ok, %{prompt_template: prompt}}, ws), do: default_prompt(prompt, ws)

  defp prompt_template!({:error, reason}, _ws) do
    raise RuntimeError, "workflow_unavailable: #{inspect(reason)}"
  end

  defp parse_template!(prompt) when is_binary(prompt) do
    Rescue.rescue_map(
      fn -> Solid.parse!(prompt) end,
      fn error, stacktrace ->
        reraise %RuntimeError{
                  message: "template_parse_error: #{Exception.message(error)} template=#{inspect(prompt)}"
                },
                stacktrace
      end
    )
  end

  defp to_solid_map(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), to_solid_value(value)} end)
  end

  defp to_solid_value(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp to_solid_value(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  defp to_solid_value(%Date{} = value), do: Date.to_iso8601(value)
  defp to_solid_value(%Time{} = value), do: Time.to_iso8601(value)
  defp to_solid_value(%_{} = value), do: value |> Map.from_struct() |> to_solid_map()
  defp to_solid_value(value) when is_map(value), do: to_solid_map(value)
  defp to_solid_value(value) when is_list(value), do: Enum.map(value, &to_solid_value/1)
  defp to_solid_value(value), do: value

  defp default_prompt(prompt, ws) when is_binary(prompt) do
    if String.trim(prompt) == "" do
      Config.workflow_prompt(workflow_store: ws)
    else
      prompt
    end
  end
end
