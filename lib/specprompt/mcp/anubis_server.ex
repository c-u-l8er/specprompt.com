defmodule SpecPrompt.MCP.AnubisServer do
  @moduledoc """
  SpecPrompt MCP server — Anubis-based.

  Exposes 8 tools for spec-driven AI development:
  validate, lint, generate, test_gen, test_compile, test_approve, diff, search.
  """

  use Anubis.Server,
    name: "specprompt",
    version: "0.1.0",
    capabilities: [:tools]

  component(SpecPrompt.MCP.Components.Validate)
  component(SpecPrompt.MCP.Components.Lint)
  component(SpecPrompt.MCP.Components.Generate)
  component(SpecPrompt.MCP.Components.TestGen)
  component(SpecPrompt.MCP.Components.TestCompile)
  component(SpecPrompt.MCP.Components.TestApprove)
  component(SpecPrompt.MCP.Components.Diff)
  component(SpecPrompt.MCP.Components.Search)
end
