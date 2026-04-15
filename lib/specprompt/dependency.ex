defmodule SpecPrompt.Dependency do
  @moduledoc "Parsed dependency from a SPEC.md Dependencies section."

  @enforce_keys [:name]
  defstruct [:name, :type, :location]

  @type t :: %__MODULE__{
          name: String.t(),
          type: String.t() | nil,
          location: String.t() | nil
        }
end
