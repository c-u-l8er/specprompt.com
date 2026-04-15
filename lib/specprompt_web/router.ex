defmodule SpecPromptWeb.Router do
  use SpecPromptWeb, :router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_root_layout, html: {SpecPromptWeb.Layouts, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
  end

  pipeline :api do
    plug(:accepts, ["json"])
  end

  scope "/", SpecPromptWeb do
    pipe_through(:browser)

    live("/", HomeLive, :index)
    live("/validate", ValidateLive, :index)
    live("/registry", RegistryLive, :index)
  end

  # Health check (no pipeline needed)
  scope "/api", SpecPromptWeb do
    pipe_through(:api)

    get("/health", HealthController, :index)
  end

  # MCP endpoint — Anubis StreamableHTTP
  scope "/mcp" do
    forward("/", SpecPromptWeb.MCPPlug)
  end
end
