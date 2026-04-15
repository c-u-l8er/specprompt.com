defmodule SpecPrompt.MCP.Components.Diff do
  @moduledoc "Compare two spec versions and return structured changes."

  use Anubis.Server.Component, type: :tool

  schema do
    field(:old_content, :string,
      required: true,
      description: "Old SPEC.md content"
    )

    field(:new_content, :string,
      required: true,
      description: "New SPEC.md content"
    )
  end

  @impl true
  def execute(params, frame) do
    old_md = get_param(params, :old_content)
    new_md = get_param(params, :new_content)

    with {:ok, old_spec} <- SpecPrompt.Parser.parse(old_md),
         {:ok, new_spec} <- SpecPrompt.Parser.parse(new_md) do
      result = SpecPrompt.Differ.diff(old_spec, new_spec)

      payload = %{
        from: result.from,
        to: result.to,
        changes:
          Enum.map(result.changes, fn c ->
            %{section: c.section, type: c.type, details: c.details}
          end)
      }

      {:reply,
       Anubis.Server.Response.tool()
       |> Anubis.Server.Response.structured(payload), frame}
    else
      {:error, errors} ->
        {:reply,
         Anubis.Server.Response.tool()
         |> Anubis.Server.Response.error("Parse error: #{Enum.join(errors, "; ")}"), frame}
    end
  end

  defp get_param(params, key) when is_map(params) and is_atom(key) do
    Map.get(params, key, Map.get(params, Atom.to_string(key)))
  end
end
