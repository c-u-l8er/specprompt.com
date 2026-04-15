defmodule SpecPrompt.Interop.ADL do
  @moduledoc """
  Bidirectional mapping between SPEC.md and Next Moca ADL (Agent Definition Language).

  Mapping:
  - name → agent.name
  - capabilities → tools + permissions
  - constraints.hard → governance.constraints
  - dependencies → dependencies
  - version → version
  """

  alias SpecPrompt.Spec

  @doc "Export a parsed spec to ADL JSON format."
  @spec export(Spec.t()) :: map()
  def export(%Spec{} = spec) do
    %{
      "agent" => %{
        "name" => spec.name,
        "version" => spec.version,
        "description" => spec.purpose
      },
      "tools" =>
        Enum.map(spec.capabilities, fn c ->
          %{
            "name" => "#{c.capability}_#{c.scope}",
            "description" => c.description
          }
        end),
      "permissions" =>
        Enum.map(spec.capabilities, fn c ->
          %{
            "resource" => c.capability,
            "action" => c.scope
          }
        end),
      "governance" => %{
        "constraints" =>
          spec.constraints
          |> Enum.filter(fn c -> c.type == :hard end)
          |> Enum.map(fn c -> c.text end)
      },
      "dependencies" =>
        Enum.map(spec.dependencies, fn d ->
          %{"name" => d.name, "type" => d.type}
        end)
    }
  end

  @doc "Import an ADL JSON map into a partial Spec (scaffold)."
  @spec import_spec(map()) :: Spec.t()
  def import_spec(adl) do
    agent = adl["agent"] || %{}

    capabilities =
      (adl["permissions"] || [])
      |> Enum.map(fn perm ->
        %SpecPrompt.Capability{
          capability: perm["resource"] || "unknown",
          scope: perm["action"] || "default"
        }
      end)

    constraints =
      (get_in(adl, ["governance", "constraints"]) || [])
      |> Enum.map(fn text -> %SpecPrompt.Constraint{text: text, type: :hard} end)

    dependencies =
      (adl["dependencies"] || [])
      |> Enum.map(fn d ->
        %SpecPrompt.Dependency{name: d["name"], type: d["type"]}
      end)

    Spec.new(%{
      name: agent["name"],
      version: agent["version"],
      purpose: agent["description"],
      capabilities: capabilities,
      constraints: constraints,
      dependencies: dependencies,
      adl_ref: adl["$id"]
    })
  end
end
