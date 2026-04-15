defmodule SpecPrompt.TestCompiler do
  @moduledoc """
  Compile natural language acceptance tests into Agentelic DSL assertions.

  IMPORTANT: The test compiler does NOT call LLMs. It generates a structured
  prompt that an external LLM (via Agentelic or the user's API key) processes.
  SpecPrompt is a tool, not an agent.

  Workflow:
  1. `compile/1` — generate compilation prompts for each acceptance test
  2. `apply_compilation/3` — apply LLM-generated assertions to a spec
  3. `approve/2` — mark compiled tests as human-reviewed
  4. `load_compiled/1` — load previously compiled tests from JSON
  5. `save_compiled/2` — save compiled tests to JSON

  Caching: compiled tests are keyed by `{source_hash, test_index}`.
  Unchanged tests reuse prior compilations.
  """

  alias SpecPrompt.{Spec, CompiledTest}

  @type compilation_prompt :: %{
          test_index: non_neg_integer(),
          spec_context: String.t(),
          acceptance_test: String.t(),
          capabilities: [String.t()],
          constraints: [String.t()],
          instructions: String.t()
        }

  @doc """
  Generate compilation prompts for all acceptance tests in a spec.

  Returns a list of structured prompts, one per acceptance test.
  Each prompt is designed to be sent to an LLM that will return
  the assertion mappings.
  """
  @spec compile(Spec.t()) :: [compilation_prompt()]
  def compile(%Spec{} = spec) do
    cap_strings =
      Enum.map(spec.capabilities, fn c ->
        "#{c.capability}:#{c.scope} (#{c.description || "no description"})"
      end)

    constraint_strings = Enum.map(spec.constraints, fn c -> c.text end)

    spec.acceptance_tests
    |> Enum.with_index()
    |> Enum.map(fn {test, idx} ->
      %{
        test_index: idx,
        spec_context: build_spec_context(spec),
        acceptance_test: "Given #{test.given} → #{test.expected}",
        capabilities: cap_strings,
        constraints: constraint_strings,
        instructions: compilation_instructions()
      }
    end)
  end

  @doc """
  Generate a single formatted prompt string suitable for sending to an LLM.

  This is what the MCP `spec_test_compile` tool returns — the agent does the LLM call.
  """
  @spec compilation_prompt_text(compilation_prompt()) :: String.t()
  def compilation_prompt_text(prompt) do
    """
    You are compiling a natural-language acceptance test into machine-executable assertions
    for the Agentelic testing DSL. Return ONLY valid JSON — no markdown, no explanation.

    ## Spec Context
    #{prompt.spec_context}

    ## Capabilities Available
    #{Enum.map_join(prompt.capabilities, "\n", &("- " <> &1))}

    ## Constraints
    #{Enum.map_join(prompt.constraints, "\n", &("- " <> &1))}

    ## Acceptance Test (index: #{prompt.test_index})
    #{prompt.acceptance_test}

    ## Instructions
    #{prompt.instructions}
    """
  end

  @doc """
  Apply LLM-generated compilation results to create CompiledTest structs.

  `compilations` is a list of maps with keys: test_index, setup, input, assertions.
  These come from the LLM's response to the compilation prompts.
  """
  @spec apply_compilation(Spec.t(), [map()], keyword()) :: [CompiledTest.t()]
  def apply_compilation(%Spec{} = _spec, compilations, opts \\ []) do
    model = Keyword.get(opts, :model, "unknown")
    now = DateTime.utc_now()

    Enum.map(compilations, fn comp ->
      %CompiledTest{
        test_index: comp["test_index"] || comp[:test_index],
        setup: comp["setup"] || comp[:setup],
        input: comp["input"] || comp[:input],
        assertions: comp["assertions"] || comp[:assertions] || [],
        approved: false,
        approved_by: nil,
        compiled_at: now,
        compiler_model: model
      }
    end)
  end

  @doc """
  Mark compiled tests as approved by a human reviewer.
  """
  @spec approve([CompiledTest.t()], String.t()) :: [CompiledTest.t()]
  def approve(compiled_tests, reviewer) do
    Enum.map(compiled_tests, fn ct ->
      %{ct | approved: true, approved_by: reviewer}
    end)
  end

  @doc """
  Check which compiled tests are stale (source_hash changed since compilation).
  Returns indices of tests that need recompilation.
  """
  @spec stale_tests([CompiledTest.t()], String.t(), non_neg_integer()) :: [non_neg_integer()]
  def stale_tests(compiled_tests, _current_hash, acceptance_test_count) do
    max_index = acceptance_test_count - 1

    compiled_tests
    |> Enum.filter(fn ct -> ct.test_index > max_index end)
    |> Enum.map(fn ct -> ct.test_index end)
  end

  @doc """
  Get compilation status summary for a spec.
  """
  @spec status(Spec.t(), [CompiledTest.t()]) :: map()
  def status(%Spec{} = spec, compiled_tests) do
    total = length(spec.acceptance_tests)
    compiled = length(compiled_tests)
    approved = Enum.count(compiled_tests, fn ct -> ct.approved == true end)
    unapproved = compiled - approved

    compiled_indices = MapSet.new(Enum.map(compiled_tests, & &1.test_index))
    missing = Enum.reject(0..(total - 1), &MapSet.member?(compiled_indices, &1))

    %{
      total_acceptance_tests: total,
      compiled: compiled,
      approved: approved,
      unapproved: unapproved,
      missing_indices: missing,
      ready_for_pipeline: approved == total and total > 0
    }
  end

  @doc "Load compiled tests from a JSON file."
  @spec load_compiled(String.t()) :: {:ok, [CompiledTest.t()]} | {:error, String.t()}
  def load_compiled(path) do
    case File.read(path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, list} when is_list(list) ->
            tests =
              Enum.map(list, fn item ->
                %CompiledTest{
                  test_index: item["test_index"],
                  setup: item["setup"],
                  input: item["input"],
                  assertions: item["assertions"] || [],
                  approved: item["approved"] || false,
                  approved_by: item["approved_by"],
                  compiled_at: parse_datetime(item["compiled_at"]),
                  compiler_model: item["compiler_model"]
                }
              end)

            {:ok, tests}

          {:ok, _} ->
            {:error, "Expected JSON array"}

          {:error, reason} ->
            {:error, "Invalid JSON: #{inspect(reason)}"}
        end

      {:error, reason} ->
        {:error, "Cannot read #{path}: #{:file.format_error(reason)}"}
    end
  end

  @doc "Save compiled tests to a JSON file."
  @spec save_compiled([CompiledTest.t()], String.t()) :: :ok | {:error, String.t()}
  def save_compiled(compiled_tests, path) do
    json =
      compiled_tests
      |> Enum.map(fn ct ->
        %{
          test_index: ct.test_index,
          setup: ct.setup,
          input: ct.input,
          assertions: ct.assertions,
          approved: ct.approved,
          approved_by: ct.approved_by,
          compiled_at: if(ct.compiled_at, do: DateTime.to_iso8601(ct.compiled_at)),
          compiler_model: ct.compiler_model
        }
      end)
      |> Jason.encode!(pretty: true)

    case File.write(path, json) do
      :ok -> :ok
      {:error, reason} -> {:error, "Cannot write #{path}: #{:file.format_error(reason)}"}
    end
  end

  # --- Private ---

  defp build_spec_context(%Spec{name: name, version: version, purpose: purpose}) do
    """
    Agent: #{name} v#{version}
    Purpose: #{purpose}
    """
  end

  defp compilation_instructions do
    """
    Generate a JSON object with these fields:
    - "test_index": integer (the index provided above)
    - "setup": object with "mocked_tools" mapping tool names to their mock return values
    - "input": string — the user input that triggers this test scenario
    - "assertions": array of assertion objects, each with:
      - {"type": "contains", "value": "expected text"} — output must contain this text
      - {"type": "tool_called", "tool": "tool_name", "args": {}} — this tool must be called
      - {"type": "tool_not_called", "tool": "tool_name"} — this tool must NOT be called
      - {"type": "escalated", "value": true/false} — whether escalation should occur
      - {"type": "constraint_respected", "constraint_index": N} — constraint N must be enforced

    Use the capabilities and constraints to determine which assertions are appropriate.
    Be specific about expected tool calls and their arguments where possible.
    """
  end

  defp parse_datetime(nil), do: nil

  defp parse_datetime(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end
end
