defmodule SpecPrompt.AcceptanceTest do
  @moduledoc "Parsed acceptance test from a SPEC.md Acceptance Tests section."

  @enforce_keys [:given, :expected]
  defstruct [:given, :expected, :format]

  @type test_format :: :given_then | :when_then

  @type t :: %__MODULE__{
          given: String.t(),
          expected: String.t(),
          format: test_format()
        }
end
