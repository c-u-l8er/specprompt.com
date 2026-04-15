defmodule SpecPrompt.ChangelogEntry do
  @moduledoc "Parsed changelog entry from a SPEC.md Changelog section."

  @enforce_keys [:version, :description]
  defstruct [:version, :date, :description]

  @type t :: %__MODULE__{
          version: String.t(),
          date: String.t() | nil,
          description: String.t()
        }
end
