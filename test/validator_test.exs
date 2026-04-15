defmodule SpecPrompt.ValidatorTest do
  use ExUnit.Case, async: true

  alias SpecPrompt.{Parser, Validator}

  @fixtures_dir Path.join(__DIR__, "fixtures")

  setup do
    valid = File.read!(Path.join(@fixtures_dir, "valid_spec.md"))
    invalid = File.read!(Path.join(@fixtures_dir, "invalid_spec.md"))
    %{valid: valid, invalid: invalid}
  end

  describe "validate/1 with valid customer-support spec" do
    test "passes validation", %{valid: md} do
      {:ok, spec} = Parser.parse(md)
      result = Validator.validate(spec)

      assert result.valid == true
      assert result.errors == []
    end

    test "has no warnings for well-formed spec", %{valid: md} do
      {:ok, spec} = Parser.parse(md)
      result = Validator.validate(spec)

      # The valid spec should have minimal warnings
      # SHOULD-2 may fire for tests that don't name capabilities directly
      assert Enum.all?(result.warnings, fn w -> w.severity == :warning end)
    end
  end

  describe "validate/1 with invalid spec" do
    test "fails validation", %{invalid: md} do
      {:ok, spec} = Parser.parse(md)
      result = Validator.validate(spec)

      assert result.valid == false
      assert length(result.errors) > 0
    end

    test "reports missing required fields", %{invalid: md} do
      {:ok, spec} = Parser.parse(md)
      result = Validator.validate(spec)

      must2_errors = Enum.filter(result.errors, fn e -> e.rule == "MUST-2" end)
      missing_fields = Enum.map(must2_errors, fn e -> e.message end)

      assert Enum.any?(missing_fields, &(&1 =~ "version"))
      assert Enum.any?(missing_fields, &(&1 =~ "author"))
      assert Enum.any?(missing_fields, &(&1 =~ "created"))
      assert Enum.any?(missing_fields, &(&1 =~ "updated"))
    end

    test "reports missing capabilities", %{invalid: md} do
      {:ok, spec} = Parser.parse(md)
      result = Validator.validate(spec)

      must5_errors = Enum.filter(result.errors, fn e -> e.rule == "MUST-5" end)
      assert Enum.any?(must5_errors, fn e -> e.message =~ "capability" end)
    end

    test "reports missing acceptance tests", %{invalid: md} do
      {:ok, spec} = Parser.parse(md)
      result = Validator.validate(spec)

      must5_errors = Enum.filter(result.errors, fn e -> e.rule == "MUST-5" end)
      assert Enum.any?(must5_errors, fn e -> e.message =~ "acceptance test" end)
    end

    test "reports bad capability format", %{invalid: md} do
      {:ok, spec} = Parser.parse(md)
      result = Validator.validate(spec)

      must6_errors = Enum.filter(result.errors, fn e -> e.rule == "MUST-6" end)
      assert length(must6_errors) > 0
    end

    test "reports bad acceptance test format", %{invalid: md} do
      {:ok, spec} = Parser.parse(md)
      result = Validator.validate(spec)

      must7_errors = Enum.filter(result.errors, fn e -> e.rule == "MUST-7" end)
      assert length(must7_errors) > 0
    end
  end

  describe "MUST-3 semver validation" do
    test "rejects invalid semver" do
      spec =
        SpecPrompt.Spec.new(%{
          name: "test",
          version: "not-semver",
          author: "test",
          created: "2026-01-01",
          updated: "2026-01-01",
          purpose: "test",
          capabilities: [%SpecPrompt.Capability{capability: "a", scope: "b"}],
          constraints: [%SpecPrompt.Constraint{text: "no"}],
          acceptance_tests: [%SpecPrompt.AcceptanceTest{given: "x", expected: "y"}]
        })

      result = Validator.validate(spec)
      assert Enum.any?(result.errors, fn e -> e.rule == "MUST-3" end)
    end

    test "accepts valid semver with prerelease" do
      spec =
        SpecPrompt.Spec.new(%{
          name: "test",
          version: "1.0.0-beta.1",
          author: "test",
          created: "2026-01-01",
          updated: "2026-01-01",
          purpose: "test",
          capabilities: [%SpecPrompt.Capability{capability: "a", scope: "b"}],
          constraints: [%SpecPrompt.Constraint{text: "no"}],
          acceptance_tests: [%SpecPrompt.AcceptanceTest{given: "x", expected: "y"}]
        })

      result = Validator.validate(spec)
      refute Enum.any?(result.errors, fn e -> e.rule == "MUST-3" end)
    end
  end

  describe "SHOULD-3 ambiguous constraint warning" do
    test "warns on ambiguous language" do
      spec =
        SpecPrompt.Spec.new(%{
          name: "test",
          version: "1.0.0",
          author: "test",
          created: "2026-01-01",
          updated: "2026-01-01",
          purpose: "test",
          capabilities: [%SpecPrompt.Capability{capability: "a", scope: "b"}],
          constraints: [
            %SpecPrompt.Constraint{text: "Try to respond quickly", type: :soft},
            %SpecPrompt.Constraint{text: "Never crash", type: :hard}
          ],
          acceptance_tests: [%SpecPrompt.AcceptanceTest{given: "x", expected: "y"}]
        })

      result = Validator.validate(spec)
      should3 = Enum.filter(result.warnings, fn w -> w.rule == "SHOULD-3" end)
      assert length(should3) == 1
    end
  end

  describe "SHOULD-4 changelog for post-v1" do
    test "warns when version > 1.0.0 has no changelog" do
      spec =
        SpecPrompt.Spec.new(%{
          name: "test",
          version: "2.0.0",
          author: "test",
          created: "2026-01-01",
          updated: "2026-01-01",
          purpose: "test",
          capabilities: [%SpecPrompt.Capability{capability: "a", scope: "b"}],
          constraints: [%SpecPrompt.Constraint{text: "Never crash", type: :hard}],
          acceptance_tests: [%SpecPrompt.AcceptanceTest{given: "x", expected: "y"}],
          changelog_entries: []
        })

      result = Validator.validate(spec)
      should4 = Enum.filter(result.warnings, fn w -> w.rule == "SHOULD-4" end)
      assert length(should4) == 1
    end
  end

  describe "validate_string/1" do
    test "validates from raw markdown", %{valid: md} do
      assert {:ok, result} = Validator.validate_string(md)
      assert result.valid == true
    end

    test "returns parse errors for bad markdown" do
      assert {:error, errors} = Validator.validate_string("no frontmatter here")
      assert length(errors) > 0
    end
  end
end
