defmodule SpecPrompt.MCP.Tools do
  @moduledoc """
  MCP tool definitions and handlers for all 8 SpecPrompt tools.

  Tools:
  - spec_validate: Validate a SPEC.md against the format standard
  - spec_lint: Check for best practices and common issues
  - spec_generate: Generate a SPEC.md from a natural language description
  - spec_test_gen: Generate test cases from acceptance criteria
  - spec_test_compile: Compile acceptance tests into Agentelic DSL (returns prompt, not result)
  - spec_test_approve: Mark compiled tests as human-reviewed
  - spec_diff: Compare two spec versions
  - spec_search: Search registry for specs (registry mode only)
  """

  alias SpecPrompt.{Parser, Validator, Linter, Differ, TestGenerator, TestCompiler}

  @doc "List all available tools with their schemas."
  @spec list() :: [map()]
  def list do
    [
      %{
        "name" => "spec_validate",
        "description" =>
          "Validate a SPEC.md against the SpecPrompt format standard. Returns errors and warnings.",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "content" => %{"type" => "string", "description" => "Raw SPEC.md markdown content"}
          },
          "required" => ["content"]
        }
      },
      %{
        "name" => "spec_lint",
        "description" =>
          "Lint a SPEC.md for best practices. Returns validation errors, warnings, and suggestions.",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "content" => %{"type" => "string", "description" => "Raw SPEC.md markdown content"}
          },
          "required" => ["content"]
        }
      },
      %{
        "name" => "spec_generate",
        "description" =>
          "Generate a SPEC.md scaffold from a natural language description. Returns a complete SPEC.md template.",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "description" => %{
              "type" => "string",
              "description" => "Natural language description of the agent"
            },
            "name" => %{"type" => "string", "description" => "Agent name (lowercase-hyphenated)"},
            "author" => %{"type" => "string", "description" => "Author name or team"}
          },
          "required" => ["description", "name"]
        }
      },
      %{
        "name" => "spec_test_gen",
        "description" =>
          "Generate test scaffolding from a SPEC.md's acceptance tests. Returns ExUnit test code skeleton.",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "content" => %{"type" => "string", "description" => "Raw SPEC.md markdown content"},
            "format" => %{
              "type" => "string",
              "enum" => ["exunit", "generic"],
              "description" => "Output format (default: exunit)"
            }
          },
          "required" => ["content"]
        }
      },
      %{
        "name" => "spec_test_compile",
        "description" =>
          "Compile acceptance tests into Agentelic DSL assertions. Returns compilation PROMPTS (not results) — the agent must execute the LLM call.",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "content" => %{"type" => "string", "description" => "Raw SPEC.md markdown content"},
            "test_indices" => %{
              "type" => "array",
              "items" => %{"type" => "integer"},
              "description" => "Optional: compile only specific test indices"
            }
          },
          "required" => ["content"]
        }
      },
      %{
        "name" => "spec_test_approve",
        "description" =>
          "Mark compiled tests as human-reviewed and approved for dark factory use.",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "compiled_tests_json" => %{
              "type" => "string",
              "description" => "JSON string of compiled tests array"
            },
            "reviewer" => %{
              "type" => "string",
              "description" => "Name or ID of the human reviewer"
            }
          },
          "required" => ["compiled_tests_json", "reviewer"]
        }
      },
      %{
        "name" => "spec_diff",
        "description" => "Compare two spec versions and return structured changes.",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "old_content" => %{"type" => "string", "description" => "Old SPEC.md content"},
            "new_content" => %{"type" => "string", "description" => "New SPEC.md content"}
          },
          "required" => ["old_content", "new_content"]
        }
      },
      %{
        "name" => "spec_search",
        "description" =>
          "Search the SpecPrompt registry for specs. Requires registry mode (Supabase).",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "query" => %{"type" => "string", "description" => "Search query"},
            "tags" => %{
              "type" => "array",
              "items" => %{"type" => "string"},
              "description" => "Filter by tags"
            },
            "workspace_id" => %{"type" => "string", "description" => "Workspace scope"}
          },
          "required" => ["query"]
        }
      }
    ]
  end

  @doc "Call a tool by name with arguments."
  @spec call(String.t(), map()) :: {:ok, map()} | {:error, map()}
  def call(name, args) do
    case name do
      "spec_validate" -> tool_validate(args)
      "spec_lint" -> tool_lint(args)
      "spec_generate" -> tool_generate(args)
      "spec_test_gen" -> tool_test_gen(args)
      "spec_test_compile" -> tool_test_compile(args)
      "spec_test_approve" -> tool_test_approve(args)
      "spec_diff" -> tool_diff(args)
      "spec_search" -> tool_search(args)
      _ -> {:error, %{code: -32602, message: "Unknown tool: #{name}"}}
    end
  end

  # --- Tool implementations ---

  defp tool_validate(%{"content" => content}) do
    case Validator.validate_string(content) do
      {:ok, result} ->
        {:ok,
         %{
           "content" => [
             %{
               "type" => "text",
               "text" =>
                 Jason.encode!(%{
                   valid: result.valid,
                   errors: Enum.map(result.errors, &issue_to_map/1),
                   warnings: Enum.map(result.warnings, &issue_to_map/1)
                 })
             }
           ]
         }}

      {:error, errors} ->
        {:ok,
         %{
           "content" => [
             %{"type" => "text", "text" => Jason.encode!(%{valid: false, parse_errors: errors})}
           ],
           "isError" => true
         }}
    end
  end

  defp tool_lint(%{"content" => content}) do
    case Linter.lint_string(content) do
      {:ok, result} ->
        {:ok,
         %{
           "content" => [
             %{
               "type" => "text",
               "text" =>
                 Jason.encode!(%{
                   valid: result.valid,
                   errors: Enum.map(result.errors, &issue_to_map/1),
                   warnings: Enum.map(result.warnings, &issue_to_map/1),
                   suggestions: Enum.map(result.suggestions, &issue_to_map/1)
                 })
             }
           ]
         }}

      {:error, errors} ->
        {:ok,
         %{
           "content" => [
             %{"type" => "text", "text" => Jason.encode!(%{valid: false, parse_errors: errors})}
           ],
           "isError" => true
         }}
    end
  end

  defp tool_generate(%{"description" => desc, "name" => name} = args) do
    author = args["author"] || "unknown"
    today = Date.utc_today() |> Date.to_iso8601()

    scaffold = """
    ---
    name: #{name}
    version: 0.1.0
    runtime: any
    author: #{author}
    created: #{today}
    updated: #{today}
    tags: []
    dependencies: []
    ---

    ## Purpose

    #{desc}

    ## Capabilities

    - example:read (TODO: define capabilities)

    ## Constraints

    - TODO: define behavioral constraints

    ## Acceptance Tests

    - Given TODO → expected behavior

    ## Architecture

    TODO: describe system architecture.

    ## Dependencies

    - TODO (type, location)

    ## Changelog

    - 0.1.0 (#{today}): Initial scaffold generated by SpecPrompt
    """

    {:ok, %{"content" => [%{"type" => "text", "text" => String.trim(scaffold)}]}}
  end

  defp tool_test_gen(%{"content" => content} = args) do
    format =
      case args["format"] do
        "generic" -> :generic
        _ -> :exunit
      end

    case Parser.parse(content) do
      {:ok, spec} ->
        code = TestGenerator.generate(spec, format: format)
        {:ok, %{"content" => [%{"type" => "text", "text" => code}]}}

      {:error, errors} ->
        {:ok,
         %{
           "content" => [
             %{"type" => "text", "text" => "Parse error: #{Enum.join(errors, "; ")}"}
           ],
           "isError" => true
         }}
    end
  end

  defp tool_test_compile(%{"content" => content} = args) do
    case Parser.parse(content) do
      {:ok, spec} ->
        prompts = TestCompiler.compile(spec)

        # Filter to specific indices if requested
        prompts =
          case args["test_indices"] do
            indices when is_list(indices) ->
              index_set = MapSet.new(indices)
              Enum.filter(prompts, fn p -> MapSet.member?(index_set, p.test_index) end)

            _ ->
              prompts
          end

        # Return the prompts as text — the agent does the LLM call
        prompt_texts =
          Enum.map(prompts, fn p ->
            %{
              test_index: p.test_index,
              prompt: TestCompiler.compilation_prompt_text(p)
            }
          end)

        {:ok,
         %{
           "content" => [
             %{
               "type" => "text",
               "text" =>
                 Jason.encode!(%{
                   message:
                     "Compilation prompts generated. Execute each prompt with an LLM to produce assertions.",
                   source_hash: spec.source_hash,
                   prompts: prompt_texts
                 })
             }
           ]
         }}

      {:error, errors} ->
        {:ok,
         %{
           "content" => [
             %{"type" => "text", "text" => "Parse error: #{Enum.join(errors, "; ")}"}
           ],
           "isError" => true
         }}
    end
  end

  defp tool_test_approve(%{"compiled_tests_json" => json, "reviewer" => reviewer}) do
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

        approved = TestCompiler.approve(tests, reviewer)

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

        {:ok,
         %{
           "content" => [
             %{
               "type" => "text",
               "text" =>
                 Jason.encode!(%{
                   message: "#{length(approved)} test(s) approved by #{reviewer}",
                   compiled_tests: approved_json
                 })
             }
           ]
         }}

      _ ->
        {:ok,
         %{
           "content" => [%{"type" => "text", "text" => "Invalid compiled_tests_json"}],
           "isError" => true
         }}
    end
  end

  defp tool_diff(%{"old_content" => old_md, "new_content" => new_md}) do
    with {:ok, old_spec} <- Parser.parse(old_md),
         {:ok, new_spec} <- Parser.parse(new_md) do
      result = Differ.diff(old_spec, new_spec)

      {:ok,
       %{
         "content" => [
           %{
             "type" => "text",
             "text" =>
               Jason.encode!(%{
                 from: result.from,
                 to: result.to,
                 changes:
                   Enum.map(result.changes, fn c ->
                     %{section: c.section, type: c.type, details: c.details}
                   end)
               })
           }
         ]
       }}
    else
      {:error, errors} ->
        {:ok,
         %{
           "content" => [
             %{"type" => "text", "text" => "Parse error: #{Enum.join(errors, "; ")}"}
           ],
           "isError" => true
         }}
    end
  end

  defp tool_search(%{"query" => _query} = _args) do
    # Registry mode — requires Supabase connection (Phase 4)
    {:ok,
     %{
       "content" => [
         %{
           "type" => "text",
           "text" =>
             Jason.encode!(%{
               message: "Registry search requires Supabase connection (not yet configured)",
               results: []
             })
         }
       ]
     }}
  end

  defp issue_to_map(issue) do
    %{severity: to_string(issue.severity), rule: issue.rule, message: issue.message}
  end
end
