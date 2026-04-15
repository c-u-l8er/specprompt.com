defmodule SpecPromptWeb.MCPPlug do
  @moduledoc """
  Plug that forwards MCP requests to the Anubis StreamableHTTP transport.
  """

  @behaviour Plug

  @impl true
  def init(_opts), do: []

  @impl true
  def call(conn, _opts) do
    # Add CORS headers for MCP clients
    conn =
      conn
      |> Plug.Conn.put_resp_header("access-control-allow-origin", "*")
      |> Plug.Conn.put_resp_header("access-control-allow-methods", "GET, POST, DELETE, OPTIONS")
      |> Plug.Conn.put_resp_header(
        "access-control-allow-headers",
        "content-type, accept, mcp-session-id"
      )

    if conn.method == "OPTIONS" do
      Plug.Conn.send_resp(conn, 204, "")
    else
      mcp_plug = Anubis.Server.Transport.StreamableHTTP.Plug
      opts = mcp_plug.init(server: SpecPrompt.MCP.AnubisServer)
      mcp_plug.call(conn, opts)
    end
  end
end
