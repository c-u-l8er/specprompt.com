defmodule SpecPrompt.Publisher do
  @moduledoc """
  Publish specs to registries and emit CloudEvents pipeline triggers.

  Supports:
  - Supabase registry (registry mode)
  - CloudEvents v1 ConsolidationEvent emission for dark factory pipeline
  """

  alias SpecPrompt.Spec

  @doc """
  Build a CloudEvents v1 ConsolidationEvent for a spec publish.

  This is the trigger that starts the dark factory pipeline:
  SpecPrompt → Agentelic → FleetPrompt → OpenSentience → PRISM
  """
  @spec consolidation_event(Spec.t(), keyword()) :: map()
  def consolidation_event(%Spec{} = spec, opts \\ []) do
    trigger = Keyword.get(opts, :trigger, "manual")

    compiled_tests_hash =
      if spec.compiled_tests && spec.compiled_tests != [] do
        spec.compiled_tests
        |> Jason.encode!()
        |> then(&:crypto.hash(:sha256, &1))
        |> Base.encode16(case: :lower)
      end

    %{
      "specversion" => "1.0",
      "type" => "org.pulse.consolidation_event",
      "source" => "specprompt.spec_lifecycle/consolidate_versions",
      "id" => generate_event_id(),
      "time" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "subject" => "spec/#{spec.workspace_id || "local"}/#{spec.name}/#{spec.version}",
      "datacontenttype" => "application/json",
      "data" => %{
        "workspace_id" => spec.workspace_id,
        "spec_name" => spec.name,
        "version" => spec.version,
        "source_hash" => spec.source_hash,
        "compiled_tests_hash" => compiled_tests_hash,
        "trigger" => trigger
      }
    }
  end

  @doc """
  Publish a spec to the Supabase registry.

  Requires registry mode configuration (Supabase URL + auth token).
  Returns the event that would be emitted on successful publish.
  """
  @spec publish(Spec.t(), keyword()) :: {:ok, map()} | {:error, String.t()}
  def publish(%Spec{} = spec, opts \\ []) do
    target = Keyword.get(opts, :target, :supabase)

    case target do
      :supabase ->
        # Registry mode — requires Supabase connection (Phase 4)
        {:error, "Supabase registry not yet configured. Use filesystem mode."}

      :local ->
        # Filesystem mode — just emit the event (for CI/webhook integration)
        event = consolidation_event(spec, opts)
        {:ok, event}
    end
  end

  defp generate_event_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
end
