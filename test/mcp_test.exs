defmodule SpecPrompt.MCP.ServerTest do
  use ExUnit.Case, async: true

  alias SpecPrompt.MCP.Server

  @fixtures_dir Path.join(__DIR__, "fixtures")

  setup do
    valid = File.read!(Path.join(@fixtures_dir, "valid_spec.md"))
    %{valid: valid}
  end

  describe "handle_request/1 — initialize" do
    test "returns server info" do
      result =
        Server.handle_request(%{
          "jsonrpc" => "2.0",
          "id" => 1,
          "method" => "initialize",
          "params" => %{}
        })

      assert result["id"] == 1
      assert result["result"]["protocolVersion"] == "2025-03-26"
      assert result["result"]["serverInfo"]["name"] == "specprompt"
    end
  end

  describe "handle_request/1 — tools/list" do
    test "returns 8 tools" do
      result =
        Server.handle_request(%{
          "jsonrpc" => "2.0",
          "id" => 2,
          "method" => "tools/list",
          "params" => %{}
        })

      tools = result["result"]["tools"]
      assert length(tools) == 8

      names = Enum.map(tools, & &1["name"])
      assert "spec_validate" in names
      assert "spec_lint" in names
      assert "spec_generate" in names
      assert "spec_test_gen" in names
      assert "spec_test_compile" in names
      assert "spec_test_approve" in names
      assert "spec_diff" in names
      assert "spec_search" in names
    end
  end

  describe "handle_request/1 — tools/call spec_validate" do
    test "validates valid spec", %{valid: md} do
      result =
        Server.handle_request(%{
          "jsonrpc" => "2.0",
          "id" => 3,
          "method" => "tools/call",
          "params" => %{"name" => "spec_validate", "arguments" => %{"content" => md}}
        })

      data = Jason.decode!(hd(result["result"]["content"])["text"])
      assert data["valid"] == true
      assert data["errors"] == []
    end

    test "rejects invalid spec" do
      result =
        Server.handle_request(%{
          "jsonrpc" => "2.0",
          "id" => 4,
          "method" => "tools/call",
          "params" => %{
            "name" => "spec_validate",
            "arguments" => %{"content" => "no frontmatter"}
          }
        })

      data = Jason.decode!(hd(result["result"]["content"])["text"])
      assert data["valid"] == false
    end
  end

  describe "handle_request/1 — tools/call spec_lint" do
    test "lints valid spec", %{valid: md} do
      result =
        Server.handle_request(%{
          "jsonrpc" => "2.0",
          "id" => 5,
          "method" => "tools/call",
          "params" => %{"name" => "spec_lint", "arguments" => %{"content" => md}}
        })

      data = Jason.decode!(hd(result["result"]["content"])["text"])
      assert data["valid"] == true
      assert is_list(data["suggestions"])
    end
  end

  describe "handle_request/1 — tools/call spec_generate" do
    test "generates scaffold" do
      result =
        Server.handle_request(%{
          "jsonrpc" => "2.0",
          "id" => 6,
          "method" => "tools/call",
          "params" => %{
            "name" => "spec_generate",
            "arguments" => %{
              "description" => "A billing agent that processes invoices",
              "name" => "billing-agent",
              "author" => "finance-team"
            }
          }
        })

      text = hd(result["result"]["content"])["text"]
      assert text =~ "billing-agent"
      assert text =~ "finance-team"
      assert text =~ "## Purpose"
      assert text =~ "billing agent that processes invoices"
    end
  end

  describe "handle_request/1 — tools/call spec_test_gen" do
    test "generates test scaffolding", %{valid: md} do
      result =
        Server.handle_request(%{
          "jsonrpc" => "2.0",
          "id" => 7,
          "method" => "tools/call",
          "params" => %{"name" => "spec_test_gen", "arguments" => %{"content" => md}}
        })

      text = hd(result["result"]["content"])["text"]
      assert text =~ "defmodule"
      assert text =~ "test"
    end
  end

  describe "handle_request/1 — tools/call spec_test_compile" do
    test "returns compilation prompts", %{valid: md} do
      result =
        Server.handle_request(%{
          "jsonrpc" => "2.0",
          "id" => 8,
          "method" => "tools/call",
          "params" => %{"name" => "spec_test_compile", "arguments" => %{"content" => md}}
        })

      data = Jason.decode!(hd(result["result"]["content"])["text"])
      assert data["message"] =~ "prompts generated"
      assert length(data["prompts"]) == 8
      assert is_binary(data["source_hash"])
    end

    test "filters by test_indices", %{valid: md} do
      result =
        Server.handle_request(%{
          "jsonrpc" => "2.0",
          "id" => 9,
          "method" => "tools/call",
          "params" => %{
            "name" => "spec_test_compile",
            "arguments" => %{"content" => md, "test_indices" => [0, 3]}
          }
        })

      data = Jason.decode!(hd(result["result"]["content"])["text"])
      assert length(data["prompts"]) == 2
    end
  end

  describe "handle_request/1 — tools/call spec_test_approve" do
    test "approves compiled tests" do
      compiled_json =
        Jason.encode!([
          %{
            "test_index" => 0,
            "setup" => %{},
            "input" => "test",
            "assertions" => [],
            "approved" => false
          }
        ])

      result =
        Server.handle_request(%{
          "jsonrpc" => "2.0",
          "id" => 10,
          "method" => "tools/call",
          "params" => %{
            "name" => "spec_test_approve",
            "arguments" => %{
              "compiled_tests_json" => compiled_json,
              "reviewer" => "test-reviewer"
            }
          }
        })

      data = Jason.decode!(hd(result["result"]["content"])["text"])
      assert data["message"] =~ "1 test(s) approved"
      assert hd(data["compiled_tests"])["approved"] == true
    end
  end

  describe "handle_request/1 — tools/call spec_diff" do
    test "diffs two specs", %{valid: md} do
      # Modify the valid spec to create a diff
      modified = String.replace(md, "version: 2.1.0", "version: 3.0.0")

      result =
        Server.handle_request(%{
          "jsonrpc" => "2.0",
          "id" => 11,
          "method" => "tools/call",
          "params" => %{
            "name" => "spec_diff",
            "arguments" => %{"old_content" => md, "new_content" => modified}
          }
        })

      data = Jason.decode!(hd(result["result"]["content"])["text"])
      assert data["from"] == "2.1.0"
      assert data["to"] == "3.0.0"
      assert length(data["changes"]) > 0
    end
  end

  describe "handle_request/1 — tools/call spec_search" do
    test "returns empty results (registry not configured)" do
      result =
        Server.handle_request(%{
          "jsonrpc" => "2.0",
          "id" => 12,
          "method" => "tools/call",
          "params" => %{
            "name" => "spec_search",
            "arguments" => %{"query" => "customer support"}
          }
        })

      data = Jason.decode!(hd(result["result"]["content"])["text"])
      assert data["results"] == []
    end
  end

  describe "handle_request/1 — unknown method" do
    test "returns method not found error" do
      result =
        Server.handle_request(%{
          "jsonrpc" => "2.0",
          "id" => 99,
          "method" => "unknown/method",
          "params" => %{}
        })

      assert result["error"][:code] == -32601
    end
  end
end
