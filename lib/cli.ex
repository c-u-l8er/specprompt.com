defmodule SpecPrompt.CLI do
  @moduledoc """
  CLI escript entry point for the specprompt command.

  Commands:
    specprompt validate SPEC.md                        — parse + validate, exit 0/1
    specprompt lint SPEC.md                            — validate + SHOULD warnings + suggestions
    specprompt diff FILE1 FILE2                        — diff two spec versions
    specprompt test-gen SPEC.md [--output DIR]         — generate test scaffolding
    specprompt test-compile SPEC.md --output FILE      — compile acceptance tests (generate prompts)
    specprompt test-compile SPEC.md --approve FILE     — mark compiled tests as approved
    specprompt test-compile SPEC.md --status FILE      — show compilation status
    specprompt publish SPEC.md                         — publish and emit CloudEvents trigger
  """

  def main(args) do
    case args do
      ["validate", path] ->
        cmd_validate(path)

      ["lint", path] ->
        cmd_lint(path)

      ["diff", path1, path2] ->
        cmd_diff(path1, path2)

      ["test-gen", path | rest] ->
        cmd_test_gen(path, rest)

      ["test-compile", path, "--output", output] ->
        cmd_test_compile(path, output)

      ["test-compile", path, "--approve", file] ->
        cmd_test_approve(path, file)

      ["test-compile", path, "--status", file] ->
        cmd_test_status(path, file)

      ["test-compile", path, "--approve"] ->
        cmd_test_approve(path, default_compiled_path(path))

      ["test-compile", path, "--status"] ->
        cmd_test_status(path, default_compiled_path(path))

      ["publish", path | rest] ->
        cmd_publish(path, rest)

      ["version"] ->
        IO.puts("specprompt 0.1.0")

      _ ->
        usage()
    end
  end

  defp cmd_validate(path) do
    case read_and_parse(path) do
      {:ok, spec} ->
        result = SpecPrompt.Validator.validate(spec)
        print_validation(result)

        if result.valid do
          IO.puts("\n✓ #{path} is valid")
          System.halt(0)
        else
          IO.puts("\n✗ #{path} has validation errors")
          System.halt(1)
        end

      {:error, errors} ->
        Enum.each(errors, fn e -> IO.puts("ERROR: #{e}") end)
        System.halt(1)
    end
  end

  defp cmd_lint(path) do
    case read_and_parse(path) do
      {:ok, spec} ->
        result = SpecPrompt.Linter.lint(spec)
        print_validation(%{errors: result.errors, warnings: result.warnings})
        print_suggestions(result.suggestions)

        if result.valid do
          IO.puts("\n✓ #{path} passes lint")
        else
          IO.puts("\n✗ #{path} has lint errors")
          System.halt(1)
        end

      {:error, errors} ->
        Enum.each(errors, fn e -> IO.puts("ERROR: #{e}") end)
        System.halt(1)
    end
  end

  defp cmd_diff(path1, path2) do
    with {:ok, spec1} <- read_and_parse(path1),
         {:ok, spec2} <- read_and_parse(path2) do
      result = SpecPrompt.Differ.diff(spec1, spec2)

      IO.puts("Diff: #{result.from} → #{result.to}")
      IO.puts(String.duplicate("-", 40))

      if result.changes == [] do
        IO.puts("No changes.")
      else
        Enum.each(result.changes, fn change ->
          symbol =
            case change.type do
              :added -> "+"
              :removed -> "-"
              :modified -> "~"
              _ -> " "
            end

          IO.puts("  #{symbol} #{change.section}: #{change.details}")
        end)
      end
    else
      {:error, errors} ->
        Enum.each(errors, fn e -> IO.puts("ERROR: #{e}") end)
        System.halt(1)
    end
  end

  defp cmd_test_gen(path, opts) do
    output_dir = extract_opt(opts, "--output") || "."
    format = if extract_opt(opts, "--format") == "generic", do: :generic, else: :exunit

    case read_and_parse(path) do
      {:ok, spec} ->
        code = SpecPrompt.TestGenerator.generate(spec, format: format)

        output_file = Path.join(output_dir, "#{spec.name || "spec"}_test.exs")
        File.mkdir_p!(output_dir)
        File.write!(output_file, code)
        IO.puts("Generated test scaffolding: #{output_file}")

      {:error, errors} ->
        Enum.each(errors, fn e -> IO.puts("ERROR: #{e}") end)
        System.halt(1)
    end
  end

  defp cmd_test_compile(path, output) do
    case read_and_parse(path) do
      {:ok, spec} ->
        prompts = SpecPrompt.TestCompiler.compile(spec)

        prompt_data =
          Enum.map(prompts, fn p ->
            %{
              test_index: p.test_index,
              prompt: SpecPrompt.TestCompiler.compilation_prompt_text(p)
            }
          end)

        json =
          Jason.encode!(
            %{
              source_hash: spec.source_hash,
              spec_name: spec.name,
              spec_version: spec.version,
              prompts: prompt_data
            },
            pretty: true
          )

        File.write!(output, json)

        IO.puts("Generated #{length(prompts)} compilation prompts → #{output}")
        IO.puts("Next: send each prompt to an LLM, then save results as compiled tests.")
        IO.puts("      specprompt test-compile #{path} --approve <compiled.json>")

      {:error, errors} ->
        Enum.each(errors, fn e -> IO.puts("ERROR: #{e}") end)
        System.halt(1)
    end
  end

  defp cmd_test_approve(_spec_path, compiled_path) do
    case SpecPrompt.TestCompiler.load_compiled(compiled_path) do
      {:ok, tests} ->
        approved = SpecPrompt.TestCompiler.approve(tests, System.get_env("USER") || "cli-user")

        case SpecPrompt.TestCompiler.save_compiled(approved, compiled_path) do
          :ok ->
            IO.puts("Approved #{length(approved)} compiled test(s) in #{compiled_path}")

          {:error, reason} ->
            IO.puts("ERROR: #{reason}")
            System.halt(1)
        end

      {:error, reason} ->
        IO.puts("ERROR: #{reason}")
        System.halt(1)
    end
  end

  defp cmd_test_status(spec_path, compiled_path) do
    with {:ok, spec} <- read_and_parse(spec_path),
         {:ok, tests} <- SpecPrompt.TestCompiler.load_compiled(compiled_path) do
      status = SpecPrompt.TestCompiler.status(spec, tests)

      IO.puts("Test Compilation Status")
      IO.puts(String.duplicate("-", 30))
      IO.puts("  Acceptance tests:  #{status.total_acceptance_tests}")
      IO.puts("  Compiled:          #{status.compiled}")
      IO.puts("  Approved:          #{status.approved}")
      IO.puts("  Unapproved:        #{status.unapproved}")

      if status.missing_indices != [] do
        IO.puts("  Missing indices:   #{Enum.join(status.missing_indices, ", ")}")
      end

      if status.ready_for_pipeline do
        IO.puts("\n  ✓ Ready for dark factory pipeline")
      else
        IO.puts("\n  ✗ Not ready for dark factory pipeline")
      end
    else
      {:error, reason} when is_binary(reason) ->
        IO.puts("ERROR: #{reason}")
        System.halt(1)

      {:error, errors} when is_list(errors) ->
        Enum.each(errors, fn e -> IO.puts("ERROR: #{e}") end)
        System.halt(1)
    end
  end

  defp cmd_publish(path, opts) do
    trigger = extract_opt(opts, "--trigger") || "manual"

    case read_and_parse(path) do
      {:ok, spec} ->
        event = SpecPrompt.Publisher.consolidation_event(spec, trigger: trigger)
        IO.puts("CloudEvents ConsolidationEvent:")
        IO.puts(Jason.encode!(event, pretty: true))

      {:error, errors} ->
        Enum.each(errors, fn e -> IO.puts("ERROR: #{e}") end)
        System.halt(1)
    end
  end

  # --- Helpers ---

  defp read_and_parse(path) do
    case File.read(path) do
      {:ok, content} ->
        SpecPrompt.Parser.parse(content)

      {:error, reason} ->
        {:error, ["Cannot read #{path}: #{:file.format_error(reason)}"]}
    end
  end

  defp print_validation(result) do
    Enum.each(result.errors, fn issue ->
      IO.puts("  ERROR [#{issue.rule}]: #{issue.message}")
    end)

    Enum.each(result.warnings, fn issue ->
      IO.puts("  WARN  [#{issue.rule}]: #{issue.message}")
    end)
  end

  defp print_suggestions(suggestions) do
    Enum.each(suggestions, fn issue ->
      IO.puts("  HINT  [#{issue.rule}]: #{issue.message}")
    end)
  end

  defp extract_opt(opts, flag) do
    case Enum.find_index(opts, &(&1 == flag)) do
      nil -> nil
      idx -> Enum.at(opts, idx + 1)
    end
  end

  defp default_compiled_path(spec_path) do
    dir = Path.dirname(spec_path)
    Path.join(dir, "compiled_tests.json")
  end

  defp usage do
    IO.puts("""
    Usage: specprompt <command> [args]

    Commands:
      validate SPEC.md                    Validate a spec file
      lint SPEC.md                        Lint for best practices
      diff FILE1 FILE2                    Compare two spec versions
      test-gen SPEC.md [--output DIR]     Generate test scaffolding
      test-compile SPEC.md --output FILE  Generate compilation prompts
      test-compile SPEC.md --approve [F]  Approve compiled tests
      test-compile SPEC.md --status [F]   Show compilation status
      publish SPEC.md                     Emit CloudEvents trigger
      version                             Show version
    """)
  end
end
