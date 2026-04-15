defmodule SpecPrompt.InteropTest do
  use ExUnit.Case, async: true

  alias SpecPrompt.{Parser, Interop.Ampersand, Interop.ADL}

  @fixtures_dir Path.join(__DIR__, "fixtures")

  setup do
    md = File.read!(Path.join(@fixtures_dir, "valid_spec.md"))
    {:ok, spec} = Parser.parse(md)
    %{spec: spec}
  end

  describe "Ampersand export" do
    test "exports capabilities as &-prefixed IDs", %{spec: spec} do
      result = Ampersand.export(spec)

      assert result["name"] == "customer-support-v2"
      assert length(result["capabilities"]) == 5
      assert hd(result["capabilities"])["id"] == "&orders.read"
    end

    test "exports governance hard/soft split", %{spec: spec} do
      result = Ampersand.export(spec)

      assert is_list(result["governance"]["hard"])
      assert length(result["governance"]["hard"]) >= 3
    end

    test "includes metadata", %{spec: spec} do
      result = Ampersand.export(spec)

      assert result["metadata"]["source"] == "specprompt"
      assert result["metadata"]["source_hash"] == spec.source_hash
    end
  end

  describe "Ampersand import" do
    test "round-trips through export/import", %{spec: spec} do
      exported = Ampersand.export(spec)
      imported = Ampersand.import_spec(exported)

      assert imported.name == spec.name
      assert length(imported.capabilities) == length(spec.capabilities)
      assert length(imported.dependencies) == length(spec.dependencies)
    end
  end

  describe "ADL export" do
    test "exports agent definition", %{spec: spec} do
      result = ADL.export(spec)

      assert result["agent"]["name"] == "customer-support-v2"
      assert result["agent"]["version"] == "2.1.0"
      assert length(result["tools"]) == 5
      assert length(result["permissions"]) == 5
    end

    test "exports governance constraints", %{spec: spec} do
      result = ADL.export(spec)

      assert is_list(result["governance"]["constraints"])
      assert length(result["governance"]["constraints"]) >= 3
    end
  end

  describe "ADL import" do
    test "imports ADL into spec scaffold", %{spec: spec} do
      adl = ADL.export(spec)
      imported = ADL.import_spec(adl)

      assert imported.name == spec.name
      assert imported.purpose == spec.purpose
      assert length(imported.capabilities) == length(spec.capabilities)
    end
  end
end
