defmodule SpecPrompt.Differ do
  @moduledoc """
  Spec version diffing.

  Compares two parsed specs and produces a structured diff showing
  what changed between versions.
  """

  alias SpecPrompt.Spec

  @type change_type :: :added | :removed | :modified | :unchanged
  @type diff_entry :: %{section: String.t(), type: change_type(), details: String.t()}
  @type diff_result :: %{from: String.t(), to: String.t(), changes: [diff_entry()]}

  @doc "Diff two specs, returning structured changes."
  @spec diff(Spec.t(), Spec.t()) :: diff_result()
  def diff(%Spec{} = old_spec, %Spec{} = new_spec) do
    changes =
      [
        diff_field("name", old_spec.name, new_spec.name),
        diff_field("version", old_spec.version, new_spec.version),
        diff_field("runtime", old_spec.runtime, new_spec.runtime),
        diff_field("author", old_spec.author, new_spec.author),
        diff_field("purpose", old_spec.purpose, new_spec.purpose),
        diff_field("architecture", old_spec.architecture, new_spec.architecture),
        diff_list("capabilities", old_spec.capabilities, new_spec.capabilities, &cap_key/1),
        diff_list("constraints", old_spec.constraints, new_spec.constraints, &constraint_key/1),
        diff_list(
          "acceptance_tests",
          old_spec.acceptance_tests,
          new_spec.acceptance_tests,
          &test_key/1
        ),
        diff_list("dependencies", old_spec.dependencies, new_spec.dependencies, &dep_key/1),
        diff_list("tags", old_spec.tags || [], new_spec.tags || [], & &1)
      ]
      |> List.flatten()
      |> Enum.reject(fn entry -> entry.type == :unchanged end)

    %{
      from: old_spec.version || "unknown",
      to: new_spec.version || "unknown",
      changes: changes
    }
  end

  defp diff_field(section, old_val, new_val) when old_val == new_val do
    %{section: section, type: :unchanged, details: ""}
  end

  defp diff_field(section, nil, new_val) do
    %{section: section, type: :added, details: "#{inspect(new_val)}"}
  end

  defp diff_field(section, old_val, nil) do
    %{section: section, type: :removed, details: "was #{inspect(old_val)}"}
  end

  defp diff_field(section, old_val, new_val) do
    %{section: section, type: :modified, details: "#{inspect(old_val)} → #{inspect(new_val)}"}
  end

  defp diff_list(section, old_list, new_list, key_fn) do
    old_keys = MapSet.new(Enum.map(old_list, key_fn))
    new_keys = MapSet.new(Enum.map(new_list, key_fn))

    added = MapSet.difference(new_keys, old_keys)
    removed = MapSet.difference(old_keys, new_keys)

    changes = []

    changes =
      if MapSet.size(added) > 0 do
        [
          %{
            section: section,
            type: :added,
            details: "#{MapSet.size(added)} added: #{Enum.join(added, ", ")}"
          }
          | changes
        ]
      else
        changes
      end

    changes =
      if MapSet.size(removed) > 0 do
        [
          %{
            section: section,
            type: :removed,
            details: "#{MapSet.size(removed)} removed: #{Enum.join(removed, ", ")}"
          }
          | changes
        ]
      else
        changes
      end

    if changes == [] do
      [%{section: section, type: :unchanged, details: ""}]
    else
      changes
    end
  end

  defp cap_key(cap), do: "#{cap.capability}:#{cap.scope}"
  defp constraint_key(c), do: c.text
  defp test_key(t), do: "#{t.given} → #{t.expected}"
  defp dep_key(d), do: d.name
end
