defmodule SpecPrompt.TestCompilerTest do
  use ExUnit.Case, async: true

  alias SpecPrompt.{Parser, TestCompiler, CompiledTest}

  @fixtures_dir Path.join(__DIR__, "fixtures")

  setup do
    md = File.read!(Path.join(@fixtures_dir, "valid_spec.md"))
    {:ok, spec} = Parser.parse(md)
    %{spec: spec}
  end

  describe "compile/1" do
    test "generates one prompt per acceptance test", %{spec: spec} do
      prompts = TestCompiler.compile(spec)
      assert length(prompts) == 8
    end

    test "each prompt has required fields", %{spec: spec} do
      [first | _] = TestCompiler.compile(spec)

      assert first.test_index == 0
      assert is_binary(first.spec_context)
      assert is_binary(first.acceptance_test)
      assert is_list(first.capabilities)
      assert length(first.capabilities) == 5
      assert is_list(first.constraints)
      assert length(first.constraints) == 6
      assert is_binary(first.instructions)
    end

    test "prompt references the correct acceptance test", %{spec: spec} do
      prompts = TestCompiler.compile(spec)
      fourth = Enum.at(prompts, 3)

      assert fourth.test_index == 3
      assert fourth.acceptance_test =~ "refund request for $750"
      assert fourth.acceptance_test =~ "escalate"
    end
  end

  describe "compilation_prompt_text/1" do
    test "generates formatted LLM prompt", %{spec: spec} do
      [first | _] = TestCompiler.compile(spec)
      text = TestCompiler.compilation_prompt_text(first)

      assert text =~ "Agentelic testing DSL"
      assert text =~ "customer-support-v2"
      assert text =~ "orders:read"
      assert text =~ "tool_called"
      assert text =~ "constraint_respected"
    end
  end

  describe "apply_compilation/3" do
    test "creates CompiledTest structs from LLM results", %{spec: spec} do
      compilations = [
        %{
          "test_index" => 0,
          "setup" => %{"mocked_tools" => %{"get_order" => %{"status" => "shipped"}}},
          "input" => "What is the status of order #123?",
          "assertions" => [
            %{"type" => "contains", "value" => "shipped"},
            %{"type" => "tool_called", "tool" => "get_order", "args" => %{"id" => "123"}}
          ]
        }
      ]

      [ct] = TestCompiler.apply_compilation(spec, compilations, model: "claude-opus-4-20250514")

      assert %CompiledTest{} = ct
      assert ct.test_index == 0
      assert ct.input == "What is the status of order #123?"
      assert length(ct.assertions) == 2
      assert ct.approved == false
      assert ct.compiler_model == "claude-opus-4-20250514"
    end
  end

  describe "approve/2" do
    test "marks all tests as approved" do
      tests = [
        %CompiledTest{test_index: 0, approved: false},
        %CompiledTest{test_index: 1, approved: false}
      ]

      approved = TestCompiler.approve(tests, "reviewer@example.com")

      assert Enum.all?(approved, fn ct -> ct.approved == true end)
      assert Enum.all?(approved, fn ct -> ct.approved_by == "reviewer@example.com" end)
    end
  end

  describe "status/2" do
    test "reports compilation status", %{spec: spec} do
      compiled = [
        %CompiledTest{test_index: 0, approved: true},
        %CompiledTest{test_index: 1, approved: false}
      ]

      status = TestCompiler.status(spec, compiled)

      assert status.total_acceptance_tests == 8
      assert status.compiled == 2
      assert status.approved == 1
      assert status.unapproved == 1
      assert length(status.missing_indices) == 6
      assert status.ready_for_pipeline == false
    end

    test "ready when all tests compiled and approved", %{spec: spec} do
      compiled =
        Enum.map(0..7, fn i ->
          %CompiledTest{test_index: i, approved: true}
        end)

      status = TestCompiler.status(spec, compiled)
      assert status.ready_for_pipeline == true
    end
  end

  describe "load_compiled/1 and save_compiled/2" do
    test "round-trips compiled tests through JSON" do
      tests = [
        %CompiledTest{
          test_index: 0,
          setup: %{"mocked_tools" => %{}},
          input: "test input",
          assertions: [%{"type" => "contains", "value" => "test"}],
          approved: false,
          compiled_at: ~U[2026-02-22 10:00:00Z],
          compiler_model: "test-model"
        }
      ]

      path = Path.join(System.tmp_dir!(), "specprompt_test_compiled_#{:rand.uniform(10000)}.json")

      on_exit(fn -> File.rm(path) end)

      assert :ok = TestCompiler.save_compiled(tests, path)
      assert {:ok, loaded} = TestCompiler.load_compiled(path)

      assert length(loaded) == 1
      [ct] = loaded
      assert ct.test_index == 0
      assert ct.input == "test input"
      assert ct.approved == false
    end

    test "loads fixture compiled tests" do
      path = Path.join(@fixtures_dir, "compiled_tests.json")
      assert {:ok, tests} = TestCompiler.load_compiled(path)
      assert length(tests) == 2
      assert hd(tests).test_index == 0
    end
  end
end
