defmodule SpecPrompt.Linter do
  @moduledoc """
  Best-practice linting for SPEC.md files.

  Runs validation (MUST + SHOULD rules) plus additional lint-specific checks
  for style, completeness, and maintainability.
  """

  alias SpecPrompt.{Spec, Validator}

  @type lint_result :: %{
          valid: boolean(),
          errors: [Validator.issue()],
          warnings: [Validator.issue()],
          suggestions: [Validator.issue()]
        }

  @doc "Lint a parsed spec — validation plus best-practice suggestions."
  @spec lint(Spec.t()) :: lint_result()
  def lint(%Spec{} = spec) do
    validation = Validator.validate(spec)
    suggestions = lint_suggestions(spec)

    %{
      valid: validation.valid,
      errors: validation.errors,
      warnings: validation.warnings,
      suggestions: suggestions
    }
  end

  @doc "Lint a raw markdown string."
  @spec lint_string(String.t()) :: {:ok, lint_result()} | {:error, [String.t()]}
  def lint_string(markdown) do
    case SpecPrompt.Parser.parse(markdown) do
      {:ok, spec} -> {:ok, lint(spec)}
      {:error, errors} -> {:error, errors}
    end
  end

  defp lint_suggestions(spec) do
    [
      check_purpose_length(spec),
      check_test_coverage(spec),
      check_dependency_details(spec),
      check_constraint_specificity(spec),
      check_tags(spec)
    ]
    |> List.flatten()
  end

  # Purpose should be substantive (at least 20 words)
  defp check_purpose_length(%Spec{purpose: nil}), do: []

  defp check_purpose_length(%Spec{purpose: purpose}) do
    word_count = purpose |> String.split(~r/\s+/) |> length()

    if word_count < 20 do
      [
        %{
          severity: :suggestion,
          rule: "LINT-1",
          message: "Purpose section is brief (#{word_count} words) — consider adding more context"
        }
      ]
    else
      []
    end
  end

  # Should have at least 2 acceptance tests per capability
  defp check_test_coverage(%Spec{capabilities: caps, acceptance_tests: tests}) do
    ratio = if length(caps) > 0, do: length(tests) / length(caps), else: 0

    if ratio < 1.5 and length(caps) > 0 do
      [
        %{
          severity: :suggestion,
          rule: "LINT-2",
          message:
            "Low test-to-capability ratio (#{length(tests)} tests / #{length(caps)} capabilities) — consider adding more acceptance tests"
        }
      ]
    else
      []
    end
  end

  # Dependencies should include type/location detail
  defp check_dependency_details(%Spec{dependencies: deps}) do
    bare = Enum.filter(deps, fn d -> is_nil(d.type) and is_nil(d.location) end)

    if length(bare) > 0 do
      [
        %{
          severity: :suggestion,
          rule: "LINT-3",
          message:
            "#{length(bare)} dependency/dependencies lack type/location details — e.g., '- name (MCP server, local)'"
        }
      ]
    else
      []
    end
  end

  # Constraints should be specific — flag very short ones
  defp check_constraint_specificity(%Spec{constraints: constraints}) do
    short = Enum.filter(constraints, fn c -> String.length(c.text) < 15 end)

    if length(short) > 0 do
      [
        %{
          severity: :suggestion,
          rule: "LINT-4",
          message: "#{length(short)} constraint(s) are very short — consider being more specific"
        }
      ]
    else
      []
    end
  end

  # Tags help discoverability
  defp check_tags(%Spec{tags: tags}) when is_list(tags) and length(tags) > 0, do: []

  defp check_tags(_spec) do
    [
      %{
        severity: :suggestion,
        rule: "LINT-5",
        message: "No tags in frontmatter — tags help with discoverability in registries"
      }
    ]
  end
end
