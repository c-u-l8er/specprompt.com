defmodule SpecPrompt.MCP.Components.TestApprove do
  @moduledoc "Mark compiled tests as human-reviewed and approved for dark factory use."

  use Anubis.Server.Component, type: :tool

  schema do
    field(:compiled_tests_json, :string,
      required: true,
      description: "JSON string of compiled tests array"
    )

    field(:reviewer, :string,
      required: true,
      description: "Name or ID of the human reviewer"
    )
  end

  @impl true
  def execute(params, frame) do
    json = get_param(params, :compiled_tests_json)
    reviewer = get_param(params, :reviewer)

    case Jason.decode(json) do
      {:ok, list} when is_list(list) ->
        tests =
          Enum.map(list, fn item ->
            %SpecPrompt.CompiledTest{
              test_index: item["test_index"],
              setup: item["setup"],
              input: item["input"],
              assertions: item["assertions"] || [],
              approved: item["approved"] || false,
              approved_by: item["approved_by"],
              compiler_model: item["compiler_model"]
            }
          end)

        approved = SpecPrompt.TestCompiler.approve(tests, reviewer)

        approved_json =
          Enum.map(approved, fn ct ->
            %{
              test_index: ct.test_index,
              setup: ct.setup,
              input: ct.input,
              assertions: ct.assertions,
              approved: ct.approved,
              approved_by: ct.approved_by,
              compiler_model: ct.compiler_model
            }
          end)

        payload = %{
          message: "#{length(approved)} test(s) approved by #{reviewer}",
          compiled_tests: approved_json
        }

        {:reply,
         Anubis.Server.Response.tool()
         |> Anubis.Server.Response.structured(payload), frame}

      _ ->
        {:reply,
         Anubis.Server.Response.tool()
         |> Anubis.Server.Response.error("Invalid compiled_tests_json"), frame}
    end
  end

  defp get_param(params, key) when is_map(params) and is_atom(key) do
    Map.get(params, key, Map.get(params, Atom.to_string(key)))
  end
end
