defmodule SpecPrompt.Interop.Ampersand do
  @moduledoc """
  Bidirectional mapping between SPEC.md and ampersand.json.

  Export: SPEC.md → ampersand.json (capability/constraint mapping)
  Import: ampersand.json → SPEC.md scaffold
  """

  alias SpecPrompt.Spec

  @doc "Export a parsed spec to ampersand.json format."
  @spec export(Spec.t()) :: map()
  def export(%Spec{} = spec) do
    %{
      "$schema" => "https://ampersandbox.design/schemas/ampersand.v0.3.json",
      "name" => spec.name,
      "version" => spec.version,
      "capabilities" =>
        Enum.map(spec.capabilities, fn c ->
          %{
            "id" => "&#{c.capability}.#{c.scope}",
            "description" => c.description
          }
        end),
      "governance" => %{
        "hard" =>
          spec.constraints
          |> Enum.filter(fn c -> c.type == :hard end)
          |> Enum.map(fn c -> c.text end),
        "soft" =>
          spec.constraints
          |> Enum.filter(fn c -> c.type == :soft end)
          |> Enum.map(fn c -> c.text end)
      },
      "dependencies" =>
        Enum.map(spec.dependencies, fn d ->
          base = %{"name" => d.name}

          base
          |> maybe_put("type", d.type)
          |> maybe_put("location", d.location)
        end),
      "metadata" => %{
        "source" => "specprompt",
        "spec_version" => spec.version,
        "source_hash" => spec.source_hash
      }
    }
  end

  @doc "Import an ampersand.json map into a partial Spec (scaffold)."
  @spec import_spec(map()) :: Spec.t()
  def import_spec(ampersand) do
    capabilities =
      (ampersand["capabilities"] || [])
      |> Enum.map(fn cap ->
        {capability, scope} = parse_ampersand_id(cap["id"] || "")

        %SpecPrompt.Capability{
          capability: capability,
          scope: scope,
          description: cap["description"],
          maps_to: cap["id"]
        }
      end)

    hard_constraints =
      (get_in(ampersand, ["governance", "hard"]) || [])
      |> Enum.map(fn text -> %SpecPrompt.Constraint{text: text, type: :hard} end)

    soft_constraints =
      (get_in(ampersand, ["governance", "soft"]) || [])
      |> Enum.map(fn text -> %SpecPrompt.Constraint{text: text, type: :soft} end)

    dependencies =
      (ampersand["dependencies"] || [])
      |> Enum.map(fn d ->
        %SpecPrompt.Dependency{
          name: d["name"],
          type: d["type"],
          location: d["location"]
        }
      end)

    Spec.new(%{
      name: ampersand["name"],
      version: ampersand["version"],
      capabilities: capabilities,
      constraints: hard_constraints ++ soft_constraints,
      dependencies: dependencies,
      ampersand_ref: ampersand["$id"]
    })
  end

  defp parse_ampersand_id(id) do
    case String.trim_leading(id, "&") |> String.split(".", parts: 2) do
      [cap, scope] -> {cap, scope}
      [cap] -> {cap, "default"}
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
