defmodule SpecPromptWeb.HomeLive do
  use SpecPromptWeb, :live_view

  @tools [
    %{name: "spec_validate", desc: "Validate a SPEC.md against the format standard"},
    %{name: "spec_lint", desc: "Check for best practices and common issues"},
    %{name: "spec_generate", desc: "Generate a SPEC.md scaffold from description"},
    %{name: "spec_test_gen", desc: "Generate test scaffolding from acceptance criteria"},
    %{name: "spec_test_compile", desc: "Compile acceptance tests into Agentelic DSL"},
    %{name: "spec_test_approve", desc: "Mark compiled tests as human-reviewed"},
    %{name: "spec_diff", desc: "Compare two spec versions"},
    %{name: "spec_search", desc: "Search the registry for specs"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "SpecPrompt",
       tools: @tools,
       registry_configured: SpecPrompt.Registry.configured?()
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-12">
      <section class="text-center py-12">
        <h1 class="text-4xl font-bold text-white mb-4">Specs, Not Prompts</h1>
        <p class="text-lg text-gray-400 max-w-2xl mx-auto">
          Open standard and toolchain for spec-driven AI development.
          Define agent behavior in machine-parseable Markdown.
        </p>
      </section>

      <section>
        <h2 class="text-xl font-semibold text-white mb-6">MCP Tools</h2>
        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div
            :for={tool <- @tools}
            class="rounded-lg border border-gray-800 bg-gray-900 p-4 hover:border-gray-700 transition"
          >
            <div class="font-mono text-sm text-emerald-400 mb-1">{tool.name}</div>
            <div class="text-sm text-gray-400">{tool.desc}</div>
          </div>
        </div>
      </section>

      <section class="grid grid-cols-1 md:grid-cols-3 gap-6">
        <a
          href={~p"/validate"}
          class="rounded-lg border border-gray-800 bg-gray-900 p-6 hover:border-emerald-700 transition group"
        >
          <h3 class="text-lg font-semibold text-white group-hover:text-emerald-400 transition mb-2">
            Validate
          </h3>
          <p class="text-sm text-gray-400">
            Paste a SPEC.md and get instant validation and lint results.
          </p>
        </a>

        <a
          href={~p"/registry"}
          class="rounded-lg border border-gray-800 bg-gray-900 p-6 hover:border-emerald-700 transition group"
        >
          <h3 class="text-lg font-semibold text-white group-hover:text-emerald-400 transition mb-2">
            Registry
          </h3>
          <p class="text-sm text-gray-400">
            Browse and search published specs.
            <span :if={!@registry_configured} class="text-yellow-500">(Not connected)</span>
          </p>
        </a>

        <div class="rounded-lg border border-gray-800 bg-gray-900 p-6">
          <h3 class="text-lg font-semibold text-white mb-2">MCP Endpoint</h3>
          <p class="text-sm text-gray-400 mb-2">Connect via MCP protocol:</p>
          <code class="text-xs text-emerald-400 font-mono bg-gray-800 px-2 py-1 rounded">
            POST /mcp
          </code>
        </div>
      </section>

      <section class="text-center text-sm text-gray-500 pb-8">
        <p>
          Part of the
          <a href="https://ampersandbox.design" class="text-gray-400 hover:text-white">[&] Protocol</a>
          ecosystem
        </p>
      </section>
    </div>
    """
  end
end
