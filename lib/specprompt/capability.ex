defmodule SpecPrompt.Capability do
  @moduledoc "Parsed capability from a SPEC.md Capabilities section."

  @enforce_keys [:capability, :scope]
  defstruct [:capability, :scope, :description, :maps_to]

  @type t :: %__MODULE__{
          capability: String.t(),
          scope: String.t(),
          description: String.t() | nil,
          maps_to: String.t() | nil
        }
end
