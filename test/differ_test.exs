defmodule SpecPrompt.DifferTest do
  use ExUnit.Case, async: true

  alias SpecPrompt.{Spec, Capability, Constraint, AcceptanceTest, Differ}

  test "diff identical specs shows no changes" do
    spec =
      Spec.new(%{
        name: "test",
        version: "1.0.0",
        capabilities: [%Capability{capability: "a", scope: "b"}],
        constraints: [%Constraint{text: "no", type: :hard}],
        acceptance_tests: [%AcceptanceTest{given: "x", expected: "y"}],
        tags: ["test"]
      })

    result = Differ.diff(spec, spec)
    assert result.changes == []
  end

  test "diff detects version change" do
    old = Spec.new(%{name: "test", version: "1.0.0"})
    new = Spec.new(%{name: "test", version: "2.0.0"})

    result = Differ.diff(old, new)
    version_changes = Enum.filter(result.changes, fn c -> c.section == "version" end)
    assert length(version_changes) == 1
    assert hd(version_changes).type == :modified
  end

  test "diff detects added capability" do
    old = Spec.new(%{capabilities: [%Capability{capability: "a", scope: "b"}]})

    new =
      Spec.new(%{
        capabilities: [
          %Capability{capability: "a", scope: "b"},
          %Capability{capability: "c", scope: "d"}
        ]
      })

    result = Differ.diff(old, new)
    cap_changes = Enum.filter(result.changes, fn c -> c.section == "capabilities" end)
    assert Enum.any?(cap_changes, fn c -> c.type == :added end)
  end

  test "diff detects removed constraint" do
    old =
      Spec.new(%{
        constraints: [
          %Constraint{text: "Never crash", type: :hard},
          %Constraint{text: "Be fast", type: :soft}
        ]
      })

    new = Spec.new(%{constraints: [%Constraint{text: "Never crash", type: :hard}]})

    result = Differ.diff(old, new)
    constraint_changes = Enum.filter(result.changes, fn c -> c.section == "constraints" end)
    assert Enum.any?(constraint_changes, fn c -> c.type == :removed end)
  end
end
