defmodule SpecPrompt.MCP.Server do
  @moduledoc """
  MCP JSON-RPC server for SpecPrompt.

  Implements MCP protocol v2025-03-26 over HTTP.
  Handles initialize, tools/list, and tools/call methods.
  """

  alias SpecPrompt.MCP.Tools

  @mcp_version "2025-03-26"
  @server_name "specprompt"
  @server_version "0.1.0"

  @doc "Handle a JSON-RPC request and return a JSON-RPC response."
  @spec handle_request(map()) :: map()
  def handle_request(%{"method" => method} = request) do
    id = request["id"]

    result =
      case method do
        "initialize" ->
          handle_initialize(request["params"])

        "tools/list" ->
          handle_tools_list()

        "tools/call" ->
          handle_tools_call(request["params"])

        _ ->
          {:error, %{code: -32601, message: "Method not found: #{method}"}}
      end

    case result do
      {:ok, data} ->
        %{"jsonrpc" => "2.0", "id" => id, "result" => data}

      {:error, error} ->
        %{"jsonrpc" => "2.0", "id" => id, "error" => error}
    end
  end

  def handle_request(_),
    do: %{"jsonrpc" => "2.0", "error" => %{code: -32600, message: "Invalid request"}}

  defp handle_initialize(_params) do
    {:ok,
     %{
       "protocolVersion" => @mcp_version,
       "capabilities" => %{"tools" => %{}},
       "serverInfo" => %{
         "name" => @server_name,
         "version" => @server_version
       }
     }}
  end

  defp handle_tools_list do
    {:ok, %{"tools" => Tools.list()}}
  end

  defp handle_tools_call(%{"name" => name, "arguments" => args}) do
    Tools.call(name, args)
  end

  defp handle_tools_call(_) do
    {:error, %{code: -32602, message: "Invalid params: name and arguments required"}}
  end
end
