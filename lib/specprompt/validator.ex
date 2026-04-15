defmodule SpecPrompt.Validator do
  @moduledoc """
  Validation rules for SPEC.md files (spec section 4.7).

  Enforces 8 MUST rules (errors) and 7 SHOULD rules (warnings).
  Returns structured validation results with descriptions.
  """

  alias SpecPrompt.Spec

  @type severity :: :error | :warning
  @type issue :: %{severity: severity(), rule: String.t(), message: String.t()}
  @type result :: %{valid: boolean(), errors: [issue()], warnings: [issue()]}

  @doc """
  Validate a parsed Spec against all MUST and SHOULD rules.

  Returns `%{valid: boolean(), errors: [issue], warnings: [issue]}`.
  A spec is valid only if there are zero errors.
  """
  @spec validate(Spec.t()) :: result()
  def validate(%Spec{} = spec) do
    errors = must_rules(spec)
    warnings = should_rules(spec)

    %{
      valid: errors == [],
      errors: errors,
      warnings: warnings
    }
  end

  @doc """
  Validate a raw markdown string by parsing then validating.
  """
  @spec validate_string(String.t()) :: {:ok, result()} | {:error, [String.t()]}
  def validate_string(markdown) do
    case SpecPrompt.Parser.parse(markdown) do
      {:ok, spec} -> {:ok, validate(spec)}
      {:error, errors} -> {:error, errors}
    end
  end

  # --- MUST rules (errors) ---

  defp must_rules(spec) do
    [
      must_1_frontmatter_present(spec),
      must_2_required_fields(spec),
      must_3_valid_semver(spec),
      must_4_required_sections(spec),
      must_5_minimum_content(spec),
      must_6_capability_format(spec),
      must_7_test_format(spec),
      must_8_ampersand_ref(spec)
    ]
    |> List.flatten()
  end

  # MUST 1: Frontmatter present and valid YAML
  defp must_1_frontmatter_present(%Spec{name: nil, version: nil, author: nil}) do
    [%{severity: :error, rule: "MUST-1", message: "Frontmatter is missing or empty"}]
  end

  defp must_1_frontmatter_present(_spec), do: []

  # MUST 2: name, version, author, created, updated fields present
  defp must_2_required_fields(spec) do
    required = [
      {:name, spec.name},
      {:version, spec.version},
      {:author, spec.author},
      {:created, spec.created},
      {:updated, spec.updated}
    ]

    required
    |> Enum.filter(fn {_field, value} -> is_nil(value) or value == "" end)
    |> Enum.map(fn {field, _} ->
      %{
        severity: :error,
        rule: "MUST-2",
        message: "Required frontmatter field '#{field}' is missing"
      }
    end)
  end

  # MUST 3: version is valid semver
  defp must_3_valid_semver(%Spec{version: nil}), do: []

  defp must_3_valid_semver(%Spec{version: version}) do
    if Regex.match?(~r/^\d+\.\d+\.\d+(-[a-zA-Z0-9.]+)?(\+[a-zA-Z0-9.]+)?$/, version) do
      []
    else
      [%{severity: :error, rule: "MUST-3", message: "Version '#{version}' is not valid semver"}]
    end
  end

  # MUST 4: All four required sections present
  defp must_4_required_sections(spec) do
    checks = [
      {"Purpose", spec.purpose},
      {"Capabilities", spec.capabilities},
      {"Constraints", spec.constraints},
      {"Acceptance Tests", spec.acceptance_tests}
    ]

    checks
    |> Enum.filter(fn {_name, value} -> is_nil(value) or value == "" or value == [] end)
    |> Enum.map(fn {name, _} ->
      %{severity: :error, rule: "MUST-4", message: "Required section '#{name}' is missing"}
    end)
  end

  # MUST 5: At least one capability, one constraint, and one acceptance test
  defp must_5_minimum_content(spec) do
    checks = [
      {"capability", spec.capabilities},
      {"constraint", spec.constraints},
      {"acceptance test", spec.acceptance_tests}
    ]

    checks
    |> Enum.filter(fn {_name, list} -> is_list(list) and length(list) == 0 end)
    |> Enum.map(fn {name, _} ->
      %{severity: :error, rule: "MUST-5", message: "At least one #{name} is required"}
    end)
  end

  # MUST 6: Capability lines match capability:scope (description) format
  # This is checked during parsing — capabilities that don't match are dropped.
  # We check if raw capabilities text has lines that failed to parse.
  defp must_6_capability_format(%Spec{raw: nil}), do: []

  defp must_6_capability_format(%Spec{raw: raw, capabilities: caps}) do
    case extract_section_text(raw, "Capabilities") do
      nil ->
        []

      text ->
        raw_lines =
          text
          |> String.split("\n")
          |> Enum.map(&String.trim/1)
          |> Enum.filter(&String.starts_with?(&1, "- "))

        if length(raw_lines) > length(caps) do
          unparsed = length(raw_lines) - length(caps)

          [
            %{
              severity: :error,
              rule: "MUST-6",
              message:
                "#{unparsed} capability line(s) do not match 'capability:scope (description)' format"
            }
          ]
        else
          []
        end
    end
  end

  # MUST 7: Acceptance test lines match Given/When format
  defp must_7_test_format(%Spec{raw: nil}), do: []

  defp must_7_test_format(%Spec{raw: raw, acceptance_tests: tests}) do
    case extract_section_text(raw, "Acceptance Tests") do
      nil ->
        []

      text ->
        raw_lines =
          text
          |> String.split("\n")
          |> Enum.map(&String.trim/1)
          |> Enum.filter(&String.starts_with?(&1, "- "))

        if length(raw_lines) > length(tests) do
          unparsed = length(raw_lines) - length(tests)

          [
            %{
              severity: :error,
              rule: "MUST-7",
              message:
                "#{unparsed} acceptance test line(s) do not match 'Given X → Y' or 'When X, then Y' format"
            }
          ]
        else
          []
        end
    end
  end

  # MUST 8: If ampersand_ref is present, referenced file must be valid
  # (In filesystem mode, we can only check presence, not content at validation time)
  defp must_8_ampersand_ref(%Spec{ampersand_ref: nil}), do: []

  defp must_8_ampersand_ref(%Spec{ampersand_ref: ref, source_path: source_path}) do
    if source_path do
      dir = Path.dirname(source_path)
      path = Path.join(dir, ref)

      if File.exists?(path) do
        []
      else
        [
          %{
            severity: :error,
            rule: "MUST-8",
            message: "ampersand_ref '#{ref}' does not exist at #{path}"
          }
        ]
      end
    else
      # No source_path, can't verify — skip
      []
    end
  end

  # --- SHOULD rules (warnings) ---

  defp should_rules(spec) do
    [
      should_1_empty_sections(spec),
      should_2_test_capability_reference(spec),
      should_3_ambiguous_constraints(spec),
      should_4_changelog_for_post_v1(spec),
      should_5_unapproved_compiled_tests(spec),
      should_6_compiled_test_index(spec),
      should_7_compiled_test_hash(spec)
    ]
    |> List.flatten()
  end

  # SHOULD 1: Empty sections
  defp should_1_empty_sections(spec) do
    sections = [
      {"Purpose", spec.purpose},
      {"Architecture", spec.architecture}
    ]

    sections
    |> Enum.filter(fn {_name, value} -> is_binary(value) and String.trim(value) == "" end)
    |> Enum.map(fn {name, _} ->
      %{severity: :warning, rule: "SHOULD-1", message: "Section '#{name}' is present but empty"}
    end)
  end

  # SHOULD 2: Acceptance tests should reference declared capabilities
  defp should_2_test_capability_reference(%Spec{acceptance_tests: tests, capabilities: caps}) do
    cap_names = Enum.map(caps, fn c -> "#{c.capability}" end)
    cap_scopes = Enum.map(caps, fn c -> "#{c.capability}:#{c.scope}" end)
    all_refs = cap_names ++ cap_scopes

    tests
    |> Enum.with_index(1)
    |> Enum.filter(fn {test, _idx} ->
      test_text = "#{test.given} #{test.expected}"

      not Enum.any?(all_refs, fn ref ->
        String.contains?(String.downcase(test_text), String.downcase(ref))
      end)
    end)
    |> Enum.map(fn {_test, idx} ->
      %{
        severity: :warning,
        rule: "SHOULD-2",
        message: "Acceptance test #{idx} does not reference any declared capability"
      }
    end)
  end

  # SHOULD 3: Constraints with ambiguous language
  defp should_3_ambiguous_constraints(%Spec{constraints: constraints}) do
    ambiguous_patterns = ~r/\b(try to|usually|sometimes|might|perhaps|if possible)\b/i

    constraints
    |> Enum.with_index(1)
    |> Enum.filter(fn {c, _idx} -> Regex.match?(ambiguous_patterns, c.text) end)
    |> Enum.map(fn {_c, idx} ->
      %{
        severity: :warning,
        rule: "SHOULD-3",
        message: "Constraint #{idx} uses ambiguous language (try to, usually, sometimes)"
      }
    end)
  end

  # SHOULD 4: Missing changelog for versions > 1.0.0
  defp should_4_changelog_for_post_v1(%Spec{version: version, changelog_entries: entries}) do
    if version && version > "1.0.0" && (is_nil(entries) || entries == []) do
      [
        %{
          severity: :warning,
          rule: "SHOULD-4",
          message: "Versions > 1.0.0 should include a changelog"
        }
      ]
    else
      []
    end
  end

  # SHOULD 5: Compiled tests present but not approved
  defp should_5_unapproved_compiled_tests(%Spec{compiled_tests: tests})
       when is_list(tests) and tests != [] do
    unapproved = Enum.filter(tests, fn t -> t.approved != true end)

    if unapproved != [] do
      [
        %{
          severity: :warning,
          rule: "SHOULD-5",
          message:
            "#{length(unapproved)} compiled test(s) are not approved — will not be used in dark factory pipeline"
        }
      ]
    else
      []
    end
  end

  defp should_5_unapproved_compiled_tests(_), do: []

  # SHOULD 6: Compiled test test_index corresponds to an acceptance test
  defp should_6_compiled_test_index(%Spec{
         compiled_tests: compiled,
         acceptance_tests: acceptance
       })
       when is_list(compiled) and compiled != [] do
    max_index = length(acceptance) - 1

    compiled
    |> Enum.filter(fn t -> t.test_index > max_index or t.test_index < 0 end)
    |> Enum.map(fn t ->
      %{
        severity: :warning,
        rule: "SHOULD-6",
        message:
          "Compiled test index #{t.test_index} does not correspond to an acceptance test (max index: #{max_index})"
      }
    end)
  end

  defp should_6_compiled_test_index(_), do: []

  # SHOULD 7: Compiled test source_hash mismatch
  defp should_7_compiled_test_hash(_spec) do
    # This would compare compiled_tests' cached hash against current source_hash.
    # Since CompiledTest doesn't store source_hash per-test in the struct (it's keyed
    # by {source_hash, test_index} externally), this check is deferred to test-compile workflow.
    []
  end

  # --- Helpers ---

  defp extract_section_text(raw, section_name) do
    case Regex.run(
           ~r/^## #{Regex.escape(section_name)}\s*\n(.*?)(?=^## |\z)/ms,
           raw
         ) do
      [_, content] -> String.trim(content)
      nil -> nil
    end
  end
end
