defmodule SpecPrompt.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        {Phoenix.PubSub, name: SpecPrompt.PubSub},
        {Anubis.Server.Registry, []}
      ] ++ mcp_children() ++ [SpecPromptWeb.Endpoint]

    opts = [strategy: :one_for_one, name: SpecPrompt.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    SpecPromptWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp mcp_children do
    [
      %{
        id: :specprompt_mcp,
        start:
          {Anubis.Server.Supervisor, :start_link,
           [
             SpecPrompt.MCP.AnubisServer,
             [transport: {:streamable_http, start: true}, request_timeout: 120_000]
           ]}
      }
    ]
  end
end
