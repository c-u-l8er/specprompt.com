defmodule SpecPrompt.Spec do
  @moduledoc """
  The parsed representation of a SPEC.md file.

  Contains all frontmatter fields and parsed section data.
  Used by both filesystem mode (local .md files) and registry mode (Supabase).
  """

  defstruct [
    :id,
    :workspace_id,
    :user_id,
    # Frontmatter
    :name,
    :version,
    :runtime,
    :author,
    :created,
    :updated,
    :tags,
    :dependency_names,
    :ampersand_ref,
    :adl_ref,
    :governance,
    :visibility,
    # Source
    :source_path,
    :source_hash,
    :repo_url,
    # Parsed sections
    :purpose,
    :capabilities,
    :constraints,
    :acceptance_tests,
    :compiled_tests,
    :architecture,
    :dependencies,
    :changelog_entries,
    # Metadata
    :parse_errors,
    :parsed_at,
    # Raw content (for source_hash computation)
    :raw
  ]

  @type t :: %__MODULE__{
          id: String.t() | nil,
          workspace_id: String.t() | nil,
          user_id: String.t() | nil,
          name: String.t() | nil,
          version: String.t() | nil,
          runtime: String.t(),
          author: String.t() | nil,
          created: String.t() | nil,
          updated: String.t() | nil,
          tags: [String.t()],
          dependency_names: [String.t()],
          ampersand_ref: String.t() | nil,
          adl_ref: String.t() | nil,
          governance: map() | nil,
          visibility: :private | :workspace | :public,
          source_path: String.t() | nil,
          source_hash: String.t() | nil,
          repo_url: String.t() | nil,
          purpose: String.t() | nil,
          capabilities: [SpecPrompt.Capability.t()],
          constraints: [SpecPrompt.Constraint.t()],
          acceptance_tests: [SpecPrompt.AcceptanceTest.t()],
          compiled_tests: [SpecPrompt.CompiledTest.t()],
          architecture: String.t() | nil,
          dependencies: [SpecPrompt.Dependency.t()],
          changelog_entries: [SpecPrompt.ChangelogEntry.t()],
          parse_errors: [String.t()],
          parsed_at: DateTime.t() | nil,
          raw: String.t() | nil
        }

  @doc "Create a new Spec with default values."
  def new(attrs \\ %{}) do
    defaults = %__MODULE__{
      runtime: "any",
      tags: [],
      dependency_names: [],
      visibility: :workspace,
      capabilities: [],
      constraints: [],
      acceptance_tests: [],
      compiled_tests: [],
      dependencies: [],
      changelog_entries: [],
      parse_errors: []
    }

    struct(defaults, attrs)
  end
end
