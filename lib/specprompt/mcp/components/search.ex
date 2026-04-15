defmodule SpecPrompt.MCP.Components.Search do
  @moduledoc "Search the SpecPrompt registry for specs. Requires registry mode (Supabase)."

  use Anubis.Server.Component, type: :tool

  schema do
    field(:query, :string,
      required: true,
      description: "Search query"
    )

    field(:tags, :string, description: "JSON array of tags to filter by")
    field(:workspace_id, :string, description: "Workspace scope")
  end

  @impl true
  def execute(_params, frame) do
    payload = %{
      message: "Registry search requires Supabase connection (not yet configured)",
      results: []
    }

    {:reply,
     Anubis.Server.Response.tool()
     |> Anubis.Server.Response.structured(payload), frame}
  end
end
