defmodule SpecPromptWeb.RegistryLive do
  use SpecPromptWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Registry - SpecPrompt",
       configured: SpecPrompt.Registry.configured?(),
       specs: [],
       query: ""
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <h1 class="text-2xl font-bold text-white">Spec Registry</h1>

      <div :if={!@configured} class="rounded-lg border border-yellow-800 bg-yellow-900/20 p-6">
        <h2 class="text-lg font-semibold text-yellow-400 mb-2">Not Connected</h2>
        <p class="text-sm text-gray-400">
          The Supabase registry is not configured. Set
          <code class="text-yellow-400 bg-gray-800 px-1 rounded">SUPABASE_URL</code>
          and
          <code class="text-yellow-400 bg-gray-800 px-1 rounded">SUPABASE_KEY</code>
          environment variables to enable the registry.
        </p>
      </div>

      <div :if={@configured} class="space-y-4">
        <form phx-submit="search" class="flex gap-3">
          <input
            type="text"
            name="query"
            value={@query}
            placeholder="Search specs..."
            class="flex-1 rounded-lg border border-gray-700 bg-gray-900 px-4 py-2 text-sm text-gray-200 placeholder-gray-600 focus:border-emerald-500 focus:ring-1 focus:ring-emerald-500 focus:outline-none"
          />
          <button
            type="submit"
            class="rounded-lg bg-emerald-600 px-6 py-2 text-sm font-medium text-white hover:bg-emerald-500 transition"
          >
            Search
          </button>
        </form>

        <div :if={@specs == []} class="text-gray-500 text-sm py-8 text-center">
          No specs found. Use the search above or publish specs via the CLI.
        </div>

        <div :for={spec <- @specs} class="rounded-lg border border-gray-800 bg-gray-900 p-4">
          <div class="font-mono text-emerald-400">{spec["name"]} v{spec["version"]}</div>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    # Registry search would go here when connected
    {:noreply, assign(socket, query: query, specs: [])}
  end
end
