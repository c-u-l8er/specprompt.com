defmodule SpecPrompt.Registry do
  @moduledoc """
  Supabase registry client for spec.specs CRUD.

  Requires registry mode — Supabase URL and auth token must be configured
  via SUPABASE_URL and SUPABASE_KEY environment variables.
  All queries are workspace-scoped via RLS.
  """

  alias SpecPrompt.Spec

  @doc "Check if registry mode is configured."
  @spec configured?() :: boolean()
  def configured? do
    supabase_url() != nil and supabase_key() != nil
  end

  @doc "Publish a spec to the registry."
  @spec publish(Spec.t(), String.t()) :: {:ok, map()} | {:error, String.t()}
  def publish(%Spec{} = spec, auth_token) do
    body =
      Jason.encode!(%{
        workspace_id: spec.workspace_id,
        user_id: spec.user_id,
        name: spec.name,
        version: spec.version,
        source_hash: spec.source_hash,
        source_path: spec.source_path,
        repo_url: spec.repo_url,
        parsed: spec_to_json(spec),
        compiled_tests: compiled_tests_to_json(spec.compiled_tests),
        visibility: to_string(spec.visibility)
      })

    post("/rest/v1/spec.specs", body, auth_token)
  end

  @doc "List specs in a workspace."
  @spec list(String.t(), String.t(), keyword()) :: {:ok, [map()]} | {:error, String.t()}
  def list(workspace_id, auth_token, opts \\ []) do
    visibility = Keyword.get(opts, :visibility)
    limit = Keyword.get(opts, :limit, 50)

    query = "workspace_id=eq.#{workspace_id}&limit=#{limit}&order=updated_at.desc"

    query =
      if visibility do
        "#{query}&visibility=eq.#{visibility}"
      else
        query
      end

    get("/rest/v1/spec.specs?#{query}", auth_token)
  end

  @doc "Get a spec by name and version."
  @spec get(String.t(), String.t(), String.t(), String.t()) ::
          {:ok, map()} | {:error, String.t()}
  def get(workspace_id, name, version, auth_token) do
    query = "workspace_id=eq.#{workspace_id}&name=eq.#{name}&version=eq.#{version}"
    get("/rest/v1/spec.specs?#{query}", auth_token)
  end

  @doc "Search specs by query (searches name and parsed->tags)."
  @spec search(String.t(), String.t(), keyword()) :: {:ok, [map()]} | {:error, String.t()}
  def search(query, auth_token, opts \\ []) do
    workspace_id = Keyword.get(opts, :workspace_id)
    tags = Keyword.get(opts, :tags, [])
    limit = Keyword.get(opts, :limit, 20)

    filters = ["name=ilike.*#{URI.encode(query)}*", "limit=#{limit}", "order=updated_at.desc"]

    filters =
      if workspace_id do
        ["workspace_id=eq.#{workspace_id}" | filters]
      else
        ["visibility=eq.public" | filters]
      end

    filters =
      if tags != [] do
        tag_filter = Enum.map_join(tags, ",", &"\"#{&1}\"")
        ["parsed->tags=cs.[#{tag_filter}]" | filters]
      else
        filters
      end

    get("/rest/v1/spec.specs?#{Enum.join(filters, "&")}", auth_token)
  end

  @doc "Update compiled tests for a spec."
  @spec update_compiled_tests(String.t(), [map()], String.t()) ::
          {:ok, map()} | {:error, String.t()}
  def update_compiled_tests(spec_id, compiled_tests, auth_token) do
    body = Jason.encode!(%{compiled_tests: compiled_tests, updated_at: DateTime.utc_now()})
    patch("/rest/v1/spec.specs?id=eq.#{spec_id}", body, auth_token)
  end

  @doc "Delete a spec."
  @spec delete(String.t(), String.t()) :: :ok | {:error, String.t()}
  def delete(spec_id, auth_token) do
    case request(:delete, "/rest/v1/spec.specs?id=eq.#{spec_id}", nil, auth_token) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  # --- HTTP helpers ---

  defp get(path, auth_token) do
    request(:get, path, nil, auth_token)
  end

  defp post(path, body, auth_token) do
    request(:post, path, body, auth_token)
  end

  defp patch(path, body, auth_token) do
    request(:patch, path, body, auth_token)
  end

  defp request(method, path, body, auth_token) do
    unless configured?() do
      {:error, "Registry mode not configured. Set SUPABASE_URL and SUPABASE_KEY."}
    else
      url = "#{supabase_url()}#{path}"

      headers =
        [
          {"apikey", supabase_key()},
          {"Authorization", "Bearer #{auth_token}"},
          {"Content-Type", "application/json"},
          {"Prefer", "return=representation"}
        ]

      # Use Erlang :httpc for zero-dependency HTTP
      # :inets and :ssl are started via extra_applications in mix.exs

      request_tuple =
        case method do
          :get ->
            {to_charlist(url),
             Enum.map(headers, fn {k, v} -> {to_charlist(k), to_charlist(v)} end)}

          :delete ->
            {to_charlist(url),
             Enum.map(headers, fn {k, v} -> {to_charlist(k), to_charlist(v)} end)}

          _ ->
            {to_charlist(url),
             Enum.map(headers, fn {k, v} -> {to_charlist(k), to_charlist(v)} end),
             ~c"application/json", body}
        end

      http_method = if method in [:get, :delete], do: :get, else: method

      case :httpc.request(http_method, request_tuple, [{:ssl, []}], []) do
        {:ok, {{_, status, _}, _headers, resp_body}} when status in 200..299 ->
          case Jason.decode(to_string(resp_body)) do
            {:ok, data} -> {:ok, data}
            {:error, _} -> {:ok, to_string(resp_body)}
          end

        {:ok, {{_, status, _}, _headers, resp_body}} ->
          {:error, "HTTP #{status}: #{to_string(resp_body)}"}

        {:error, reason} ->
          {:error, "HTTP error: #{inspect(reason)}"}
      end
    end
  end

  # --- Serialization helpers ---

  defp spec_to_json(%Spec{} = spec) do
    %{
      name: spec.name,
      version: spec.version,
      runtime: spec.runtime,
      author: spec.author,
      created: spec.created,
      updated: spec.updated,
      tags: spec.tags || [],
      purpose: spec.purpose,
      capabilities:
        Enum.map(spec.capabilities, fn c ->
          %{capability: c.capability, scope: c.scope, description: c.description}
        end),
      constraints:
        Enum.map(spec.constraints, fn c ->
          %{text: c.text, type: to_string(c.type)}
        end),
      acceptance_tests:
        Enum.map(spec.acceptance_tests, fn t ->
          %{given: t.given, expected: t.expected, format: to_string(t.format)}
        end),
      architecture: spec.architecture,
      dependencies:
        Enum.map(spec.dependencies, fn d ->
          %{name: d.name, type: d.type, location: d.location}
        end),
      changelog_entries:
        Enum.map(spec.changelog_entries, fn e ->
          %{version: e.version, date: e.date, description: e.description}
        end)
    }
  end

  defp compiled_tests_to_json(nil), do: []
  defp compiled_tests_to_json([]), do: []

  defp compiled_tests_to_json(tests) do
    Enum.map(tests, fn ct ->
      %{
        test_index: ct.test_index,
        setup: ct.setup,
        input: ct.input,
        assertions: ct.assertions,
        approved: ct.approved,
        approved_by: ct.approved_by,
        compiler_model: ct.compiler_model
      }
    end)
  end

  defp supabase_url, do: System.get_env("SUPABASE_URL")
  defp supabase_key, do: System.get_env("SUPABASE_KEY")
end
