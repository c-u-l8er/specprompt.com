defmodule SpecPromptWeb.HealthController do
  use SpecPromptWeb, :controller

  def index(conn, _params) do
    json(conn, %{
      status: "ok",
      name: "specprompt",
      version: "0.1.0",
      registry: SpecPrompt.Registry.configured?()
    })
  end
end
