defmodule SpecPrompt.LinterTest do
  use ExUnit.Case, async: true

  alias SpecPrompt.{Parser, Linter}

  @fixtures_dir Path.join(__DIR__, "fixtures")

  test "lint valid spec returns suggestions" do
    md = File.read!(Path.join(@fixtures_dir, "valid_spec.md"))
    {:ok, spec} = Parser.parse(md)
    result = Linter.lint(spec)

    assert result.valid == true
    assert is_list(result.suggestions)
  end

  test "lint_string works on raw markdown" do
    md = File.read!(Path.join(@fixtures_dir, "valid_spec.md"))
    assert {:ok, result} = Linter.lint_string(md)
    assert result.valid == true
  end

  test "lint suggests tags when missing" do
    spec =
      SpecPrompt.Spec.new(%{
        name: "test",
        version: "1.0.0",
        author: "test",
        created: "2026-01-01",
        updated: "2026-01-01",
        purpose: "A test agent that does things for testing purposes in the system.",
        capabilities: [%SpecPrompt.Capability{capability: "a", scope: "b"}],
        constraints: [%SpecPrompt.Constraint{text: "Never crash", type: :hard}],
        acceptance_tests: [%SpecPrompt.AcceptanceTest{given: "x", expected: "y"}],
        tags: []
      })

    result = Linter.lint(spec)
    assert Enum.any?(result.suggestions, fn s -> s.rule == "LINT-5" end)
  end
end
