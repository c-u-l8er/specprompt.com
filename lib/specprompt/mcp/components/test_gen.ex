defmodule SpecPrompt.MCP.Components.TestGen do
  @moduledoc "Generate test scaffolding from a SPEC.md's acceptance tests."

  use Anubis.Server.Component, type: :tool

  schema do
    field(:content, :string,
      required: true,
      description: "Raw SPEC.md markdown content"
    )

    field(:format, :string, description: "Output format: exunit or generic (default: exunit)")
  end

  @impl true
  def execute(params, frame) do
    content = get_param(params, :content)

    format =
      case get_param(params, :format) do
        "generic" -> :generic
        _ -> :exunit
      end

    case SpecPrompt.Parser.parse(content) do
      {:ok, spec} ->
        code = SpecPrompt.TestGenerator.generate(spec, format: format)

        {:reply,
         Anubis.Server.Response.tool()
         |> Anubis.Server.Response.text(code), frame}

      {:error, errors} ->
        {:reply,
         Anubis.Server.Response.tool()
         |> Anubis.Server.Response.error("Parse error: #{Enum.join(errors, "; ")}"), frame}
    end
  end

  defp get_param(params, key, default \\ nil) when is_map(params) and is_atom(key) do
    Map.get(params, key, Map.get(params, Atom.to_string(key), default))
  end
end
