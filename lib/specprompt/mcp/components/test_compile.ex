defmodule SpecPrompt.MCP.Components.TestCompile do
  @moduledoc "Compile acceptance tests into Agentelic DSL assertions. Returns compilation prompts."

  use Anubis.Server.Component, type: :tool

  schema do
    field(:content, :string,
      required: true,
      description: "Raw SPEC.md markdown content"
    )

    field(:test_indices, :string, description: "JSON array of test indices to compile (optional)")
  end

  @impl true
  def execute(params, frame) do
    content = get_param(params, :content)

    case SpecPrompt.Parser.parse(content) do
      {:ok, spec} ->
        prompts = SpecPrompt.TestCompiler.compile(spec)

        prompts =
          case parse_indices(get_param(params, :test_indices)) do
            nil ->
              prompts

            indices ->
              index_set = MapSet.new(indices)
              Enum.filter(prompts, fn p -> MapSet.member?(index_set, p.test_index) end)
          end

        prompt_texts =
          Enum.map(prompts, fn p ->
            %{
              test_index: p.test_index,
              prompt: SpecPrompt.TestCompiler.compilation_prompt_text(p)
            }
          end)

        payload = %{
          message: "Compilation prompts generated. Execute each prompt with an LLM.",
          source_hash: spec.source_hash,
          prompts: prompt_texts
        }

        {:reply,
         Anubis.Server.Response.tool()
         |> Anubis.Server.Response.structured(payload), frame}

      {:error, errors} ->
        {:reply,
         Anubis.Server.Response.tool()
         |> Anubis.Server.Response.error("Parse error: #{Enum.join(errors, "; ")}"), frame}
    end
  end

  defp get_param(params, key) when is_map(params) and is_atom(key) do
    Map.get(params, key, Map.get(params, Atom.to_string(key)))
  end

  defp parse_indices(nil), do: nil
  defp parse_indices(indices) when is_list(indices), do: indices

  defp parse_indices(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, list} when is_list(list) -> list
      _ -> nil
    end
  end

  defp parse_indices(_), do: nil
end
