defmodule SpecPrompt.ParserTest do
  use ExUnit.Case, async: true

  alias SpecPrompt.{
    Parser,
    Spec,
    Capability,
    Constraint,
    AcceptanceTest,
    Dependency,
    ChangelogEntry
  }

  @fixtures_dir Path.join(__DIR__, "fixtures")

  setup do
    valid = File.read!(Path.join(@fixtures_dir, "valid_spec.md"))
    invalid = File.read!(Path.join(@fixtures_dir, "invalid_spec.md"))
    %{valid: valid, invalid: invalid}
  end

  describe "parse/1 with valid customer-support spec" do
    test "returns {:ok, %Spec{}}", %{valid: md} do
      assert {:ok, %Spec{}} = Parser.parse(md)
    end

    test "parses frontmatter fields", %{valid: md} do
      {:ok, spec} = Parser.parse(md)

      assert spec.name == "customer-support-v2"
      assert spec.version == "2.1.0"
      assert spec.runtime == "opensentience"
      assert spec.author == "ops-team"
      assert spec.created == "2026-02-15"
      assert spec.updated == "2026-02-22"
      assert spec.tags == ["support", "customer-facing", "e-commerce"]
      assert spec.dependency_names == ["graphonomous", "orders-api", "notifications-service"]
    end

    test "computes source_hash", %{valid: md} do
      {:ok, spec} = Parser.parse(md)
      assert is_binary(spec.source_hash)
      assert String.length(spec.source_hash) == 64
    end

    test "parses purpose section", %{valid: md} do
      {:ok, spec} = Parser.parse(md)
      assert spec.purpose =~ "Handle customer inquiries"
      assert spec.purpose =~ "Graphonomous"
    end

    test "parses 5 capabilities", %{valid: md} do
      {:ok, spec} = Parser.parse(md)
      assert length(spec.capabilities) == 5

      [first | _] = spec.capabilities
      assert %Capability{capability: "orders", scope: "read"} = first
      assert first.description =~ "order status"
    end

    test "parses 6 constraints", %{valid: md} do
      {:ok, spec} = Parser.parse(md)
      assert length(spec.constraints) == 6

      [first | _] = spec.constraints
      assert %Constraint{text: "Never disclose" <> _} = first
      assert first.type == :hard
    end

    test "classifies constraint types", %{valid: md} do
      {:ok, spec} = Parser.parse(md)

      types = Enum.map(spec.constraints, & &1.type)
      # "Never" and "Always" => :hard; "Rate limit" and "Response time" => :unclassified
      assert Enum.count(types, &(&1 == :hard)) >= 4
    end

    test "parses 8 acceptance tests", %{valid: md} do
      {:ok, spec} = Parser.parse(md)
      assert length(spec.acceptance_tests) == 8

      [first | _] = spec.acceptance_tests
      assert %AcceptanceTest{format: :given_then} = first
      assert first.given =~ "valid order #123"
      assert first.expected =~ "current status"
    end

    test "parses architecture section", %{valid: md} do
      {:ok, spec} = Parser.parse(md)
      assert spec.architecture =~ "Graphonomous"
      assert spec.architecture =~ "Refund workflow"
    end

    test "parses 3 dependencies with details", %{valid: md} do
      {:ok, spec} = Parser.parse(md)
      assert length(spec.dependencies) == 3

      [graphonomous | _] = spec.dependencies

      assert %Dependency{name: "graphonomous", type: "MCP server", location: "local"} =
               graphonomous
    end

    test "parses 3 changelog entries", %{valid: md} do
      {:ok, spec} = Parser.parse(md)
      assert length(spec.changelog_entries) == 3

      [first | _] = spec.changelog_entries
      assert %ChangelogEntry{version: "2.1.0", date: "2026-02-22"} = first
      assert first.description =~ "Graphonomous"
    end

    test "parse is deterministic", %{valid: md} do
      {:ok, spec1} = Parser.parse(md)
      {:ok, spec2} = Parser.parse(md)

      assert spec1.name == spec2.name
      assert spec1.source_hash == spec2.source_hash
      assert length(spec1.capabilities) == length(spec2.capabilities)
      assert length(spec1.acceptance_tests) == length(spec2.acceptance_tests)
    end
  end

  describe "parse/1 with invalid spec" do
    test "parses but has empty required sections", %{invalid: md} do
      {:ok, spec} = Parser.parse(md)

      # Name present but version/author/created/updated missing
      assert spec.name == "broken-agent"
      assert is_nil(spec.version)
      assert is_nil(spec.author)

      # Capabilities didn't parse (bad format)
      assert spec.capabilities == []

      # Acceptance tests didn't parse (bad format)
      assert spec.acceptance_tests == []
    end
  end

  describe "parse/1 with missing frontmatter" do
    test "returns error for no frontmatter" do
      assert {:error, [msg]} = Parser.parse("# No Frontmatter\n\nJust text.")
      assert msg =~ "frontmatter"
    end
  end

  describe "parse/1 with When/then format" do
    test "parses When X, then Y tests" do
      md = """
      ---
      name: test-agent
      version: 1.0.0
      author: test
      created: 2026-01-01
      updated: 2026-01-01
      ---

      ## Purpose

      A test agent.

      ## Capabilities

      - api:read (read data)

      ## Constraints

      - Never crash

      ## Acceptance Tests

      - When user asks for help, then provide assistance
      - Given error occurs → handle gracefully
      """

      {:ok, spec} = Parser.parse(md)
      assert length(spec.acceptance_tests) == 2

      [when_test, given_test] = spec.acceptance_tests
      assert when_test.format == :when_then
      assert when_test.given == "user asks for help"
      assert when_test.expected == "provide assistance"

      assert given_test.format == :given_then
    end
  end
end
