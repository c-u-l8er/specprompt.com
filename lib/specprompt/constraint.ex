defmodule SpecPrompt.Constraint do
  @moduledoc "Parsed constraint from a SPEC.md Constraints section."

  @enforce_keys [:text]
  defstruct [:text, :type, :maps_to_governance]

  @type constraint_type :: :hard | :soft | :unclassified

  @type t :: %__MODULE__{
          text: String.t(),
          type: constraint_type(),
          maps_to_governance: String.t() | nil
        }
end
