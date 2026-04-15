defmodule SpecPrompt.MCP.Components.Validate do
  @moduledoc "Validate a SPEC.md against the SpecPrompt format standard."

  use Anubis.Server.Component, type: :tool

  schema do
    field(:content, :string,
      required: true,
      description: "Raw SPEC.md markdown content"
    )
  end

  @impl true
  def execute(params, frame) do
    content = get_param(params, :content)

    case SpecPrompt.Validator.validate_string(content) do
      {:ok, result} ->
        payload = %{
          valid: result.valid,
          errors: Enum.map(result.errors, &issue_to_map/1),
          warnings: Enum.map(result.warnings, &issue_to_map/1)
        }

        {:reply,
         Anubis.Server.Response.tool()
         |> Anubis.Server.Response.structured(payload), frame}

      {:error, errors} ->
        {:reply,
         Anubis.Server.Response.tool()
         |> Anubis.Server.Response.structured(%{valid: false, parse_errors: errors})
         |> Map.put(:isError, true), frame}
    end
  end

  defp get_param(params, key) when is_map(params) and is_atom(key) do
    Map.get(params, key, Map.get(params, Atom.to_string(key)))
  end

  defp issue_to_map(issue) do
    %{severity: to_string(issue.severity), rule: issue.rule, message: issue.message}
  end
end
