defmodule SpecPrompt.Parser do
  @moduledoc """
  PEG-based SPEC.md parser.

  Parses YAML frontmatter and H2 sections into a `%SpecPrompt.Spec{}`.
  Deterministic: same input always produces the same parse tree.
  """

  alias SpecPrompt.{Spec, Capability, Constraint, AcceptanceTest, Dependency, ChangelogEntry}

  @type parse_result :: {:ok, Spec.t()} | {:error, [String.t()]}

  @doc """
  Parse a SPEC.md string into a structured Spec.

  Returns `{:ok, %Spec{}}` on success or `{:error, [errors]}` on failure.
  """
  @spec parse(String.t()) :: parse_result()
  def parse(markdown) when is_binary(markdown) do
    source_hash = :crypto.hash(:sha256, markdown) |> Base.encode16(case: :lower)

    with {:ok, frontmatter, body} <- extract_frontmatter(markdown),
         {:ok, fm_map} <- parse_yaml(frontmatter),
         {:ok, sections} <- parse_sections(body) do
      spec =
        Spec.new(%{
          name: fm_map["name"],
          version: fm_map["version"],
          runtime: fm_map["runtime"] || "any",
          author: fm_map["author"],
          created: to_string_or_nil(fm_map["created"]),
          updated: to_string_or_nil(fm_map["updated"]),
          tags: fm_map["tags"] || [],
          dependency_names: fm_map["dependencies"] || [],
          ampersand_ref: fm_map["ampersand_ref"],
          adl_ref: fm_map["adl_ref"],
          governance: fm_map["governance"],
          workspace_id: fm_map["workspace_id"],
          visibility: parse_visibility(fm_map["visibility"]),
          source_hash: source_hash,
          purpose: Map.get(sections, "Purpose"),
          capabilities: parse_capabilities(Map.get(sections, "Capabilities", "")),
          constraints: parse_constraints(Map.get(sections, "Constraints", "")),
          acceptance_tests: parse_acceptance_tests(Map.get(sections, "Acceptance Tests", "")),
          architecture: Map.get(sections, "Architecture"),
          dependencies: parse_dependencies(Map.get(sections, "Dependencies", "")),
          changelog_entries: parse_changelog(Map.get(sections, "Changelog", "")),
          parsed_at: DateTime.utc_now(),
          raw: markdown
        })

      {:ok, spec}
    end
  end

  # --- Frontmatter extraction ---

  defp extract_frontmatter(markdown) do
    case String.split(markdown, ~r/^---\s*$/m, parts: 3) do
      ["", frontmatter, body] ->
        {:ok, String.trim(frontmatter), String.trim(body)}

      ["", frontmatter | _rest] ->
        {:ok, String.trim(frontmatter), ""}

      _ ->
        {:error,
         ["line 1: Missing or invalid YAML frontmatter (must be enclosed in --- delimiters)"]}
    end
  end

  defp parse_yaml(yaml_string) do
    case YamlElixir.read_from_string(yaml_string) do
      {:ok, map} when is_map(map) ->
        {:ok, map}

      {:ok, _} ->
        {:error, ["line 1: Frontmatter must be a YAML mapping"]}

      {:error, reason} ->
        {:error, ["line 1: Invalid YAML in frontmatter: #{inspect(reason)}"]}
    end
  end

  # --- Section parsing ---

  defp parse_sections(body) do
    sections =
      body
      |> String.split(~r/^## /m)
      |> Enum.reject(&(String.trim(&1) == ""))
      |> Enum.map(fn section ->
        case String.split(section, "\n", parts: 2) do
          [heading, rest] ->
            {String.trim(heading), String.trim(rest)}

          [heading] ->
            {String.trim(heading), ""}
        end
      end)
      |> Map.new()

    {:ok, sections}
  end

  # --- Capability parsing ---
  # Format: `- capability:scope (description)`

  defp parse_capabilities(text) do
    text
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&String.starts_with?(&1, "- "))
    |> Enum.map(&parse_capability_line/1)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_capability_line(line) do
    line = String.trim_leading(line, "- ")

    case Regex.run(~r/^([a-z][a-z0-9_]*):([a-z][a-z0-9_]*)\s*\((.+)\)$/, line) do
      [_, cap, scope, desc] ->
        %Capability{capability: cap, scope: scope, description: String.trim(desc)}

      nil ->
        # Try without description parentheses
        case Regex.run(~r/^([a-z][a-z0-9_]*):([a-z][a-z0-9_]*)$/, String.trim(line)) do
          [_, cap, scope] ->
            %Capability{capability: cap, scope: scope}

          nil ->
            nil
        end
    end
  end

  # --- Constraint parsing ---

  defp parse_constraints(text) do
    text
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&String.starts_with?(&1, "- "))
    |> Enum.map(&parse_constraint_line/1)
  end

  defp parse_constraint_line(line) do
    text = String.trim_leading(line, "- ")

    type =
      cond do
        String.starts_with?(text, "Hard: ") -> :hard
        String.starts_with?(text, "Soft: ") -> :soft
        String.match?(text, ~r/^(Never|Always|Must)/i) -> :hard
        String.match?(text, ~r/^(Prefer|Try to|Usually|Sometimes)/i) -> :soft
        true -> :unclassified
      end

    %Constraint{text: text, type: type}
  end

  # --- Acceptance test parsing ---
  # Format: `- Given [X] → [Y]` or `- When [X], then [Y]`

  defp parse_acceptance_tests(text) do
    text
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&String.starts_with?(&1, "- "))
    |> Enum.map(&parse_test_line/1)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_test_line(line) do
    line = String.trim_leading(line, "- ")

    cond do
      # Given X → Y format
      String.starts_with?(line, "Given ") ->
        case String.split(String.trim_leading(line, "Given "), " → ", parts: 2) do
          [given, expected] ->
            %AcceptanceTest{
              given: String.trim(given),
              expected: String.trim(expected),
              format: :given_then
            }

          _ ->
            nil
        end

      # When X, then Y format
      String.starts_with?(line, "When ") ->
        case String.split(String.trim_leading(line, "When "), ", then ", parts: 2) do
          [condition, expected] ->
            %AcceptanceTest{
              given: String.trim(condition),
              expected: String.trim(expected),
              format: :when_then
            }

          _ ->
            nil
        end

      true ->
        nil
    end
  end

  # --- Dependency parsing ---
  # Format: `- name (type, location)` or `- name`

  defp parse_dependencies(text) do
    text
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&String.starts_with?(&1, "- "))
    |> Enum.map(&parse_dependency_line/1)
  end

  defp parse_dependency_line(line) do
    line = String.trim_leading(line, "- ")

    case Regex.run(~r/^(.+?)\s*\((.+)\)$/, line) do
      [_, name, detail] ->
        {type, location} = parse_dependency_detail(detail)
        %Dependency{name: String.trim(name), type: type, location: location}

      nil ->
        %Dependency{name: String.trim(line)}
    end
  end

  defp parse_dependency_detail(detail) do
    parts = String.split(detail, ",", parts: 2) |> Enum.map(&String.trim/1)

    case parts do
      [type, "remote: " <> location] -> {type, location}
      [type, location] -> {type, location}
      [type] -> {type, nil}
    end
  end

  # --- Changelog parsing ---
  # Format: `- version (date): description`

  defp parse_changelog(text) do
    text
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&String.starts_with?(&1, "- "))
    |> Enum.map(&parse_changelog_line/1)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_changelog_line(line) do
    line = String.trim_leading(line, "- ")

    case Regex.run(~r/^(.+?)\s*\((.+?)\):\s*(.+)$/, line) do
      [_, version, date, desc] ->
        %ChangelogEntry{
          version: String.trim(version),
          date: String.trim(date),
          description: String.trim(desc)
        }

      nil ->
        nil
    end
  end

  # --- Helpers ---

  defp parse_visibility("private"), do: :private
  defp parse_visibility("public"), do: :public
  defp parse_visibility(_), do: :workspace

  defp to_string_or_nil(nil), do: nil
  defp to_string_or_nil(%Date{} = d), do: Date.to_iso8601(d)
  defp to_string_or_nil(val), do: to_string(val)
end
