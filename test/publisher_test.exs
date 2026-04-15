defmodule SpecPrompt.PublisherTest do
  use ExUnit.Case, async: true

  alias SpecPrompt.{Parser, Publisher}

  @fixtures_dir Path.join(__DIR__, "fixtures")

  setup do
    md = File.read!(Path.join(@fixtures_dir, "valid_spec.md"))
    {:ok, spec} = Parser.parse(md)
    %{spec: spec}
  end

  describe "consolidation_event/2" do
    test "produces CloudEvents v1 envelope", %{spec: spec} do
      event = Publisher.consolidation_event(spec)

      assert event["specversion"] == "1.0"
      assert event["type"] == "org.pulse.consolidation_event"
      assert event["source"] == "specprompt.spec_lifecycle/consolidate_versions"
      assert is_binary(event["id"])
      assert is_binary(event["time"])
    end

    test "includes spec data", %{spec: spec} do
      event = Publisher.consolidation_event(spec, trigger: "git_push")

      assert event["data"]["spec_name"] == "customer-support-v2"
      assert event["data"]["version"] == "2.1.0"
      assert event["data"]["source_hash"] == spec.source_hash
      assert event["data"]["trigger"] == "git_push"
    end

    test "subject includes workspace scope", %{spec: spec} do
      event = Publisher.consolidation_event(spec)
      assert event["subject"] =~ "customer-support-v2"
      assert event["subject"] =~ "2.1.0"
    end
  end

  describe "publish/2" do
    test "local publish returns event", %{spec: spec} do
      assert {:ok, event} = Publisher.publish(spec, target: :local)
      assert event["specversion"] == "1.0"
    end

    test "supabase publish returns error (not configured)", %{spec: spec} do
      assert {:error, msg} = Publisher.publish(spec, target: :supabase)
      assert msg =~ "not yet configured"
    end
  end
end
