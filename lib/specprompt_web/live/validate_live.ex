defmodule SpecPromptWeb.ValidateLive do
  use SpecPromptWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Validate - SpecPrompt",
       content: "",
       validation_result: nil,
       lint_result: nil
     )}
  end

  @impl true
  def handle_event("validate", %{"content" => content}, socket) do
    validation_result =
      case SpecPrompt.Validator.validate_string(content) do
        {:ok, result} -> {:ok, result}
        {:error, errors} -> {:error, errors}
      end

    lint_result =
      case SpecPrompt.Linter.lint_string(content) do
        {:ok, result} -> {:ok, result}
        {:error, _} -> nil
      end

    {:noreply,
     assign(socket,
       content: content,
       validation_result: validation_result,
       lint_result: lint_result
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <h1 class="text-2xl font-bold text-white">Validate SPEC.md</h1>

      <form phx-submit="validate" class="space-y-4">
        <textarea
          name="content"
          rows="16"
          placeholder="Paste your SPEC.md content here..."
          class="w-full rounded-lg border border-gray-700 bg-gray-900 p-4 font-mono text-sm text-gray-200 placeholder-gray-600 focus:border-emerald-500 focus:ring-1 focus:ring-emerald-500 focus:outline-none"
        >{@content}</textarea>
        <button
          type="submit"
          class="rounded-lg bg-emerald-600 px-6 py-2 text-sm font-medium text-white hover:bg-emerald-500 transition"
        >
          Validate & Lint
        </button>
      </form>

      <div :if={@validation_result} class="space-y-4">
        <.result_section result={@validation_result} title="Validation" />
        <.lint_section :if={@lint_result} result={@lint_result} />
      </div>
    </div>
    """
  end

  defp result_section(assigns) do
    ~H"""
    <div class={[
      "rounded-lg border p-4",
      match?({:ok, %{valid: true}}, @result) && "border-emerald-800 bg-emerald-900/20",
      !match?({:ok, %{valid: true}}, @result) && "border-red-800 bg-red-900/20"
    ]}>
      <h2 class="text-lg font-semibold text-white mb-3">{@title}</h2>

      <div :if={match?({:ok, %{valid: true}}, @result)} class="text-emerald-400 text-sm">
        Valid SPEC.md
      </div>

      <div :if={match?({:ok, %{valid: false}}, @result)}>
        <div :for={error <- elem(@result, 1).errors} class="text-red-400 text-sm mb-1">
          <span class="font-mono text-red-500">[{error.rule}]</span> {error.message}
        </div>
      </div>

      <div :if={match?({:ok, %{warnings: [_ | _]}}, @result)}>
        <div
          :for={warning <- elem(@result, 1).warnings}
          class="text-yellow-400 text-sm mb-1 mt-2"
        >
          <span class="font-mono text-yellow-500">[{warning.rule}]</span> {warning.message}
        </div>
      </div>

      <div :if={match?({:error, _}, @result)}>
        <div :for={error <- elem(@result, 1)} class="text-red-400 text-sm mb-1">
          Parse error: {error}
        </div>
      </div>
    </div>
    """
  end

  defp lint_section(assigns) do
    ~H"""
    <div :if={match?({:ok, _}, @result)} class="rounded-lg border border-gray-800 bg-gray-900 p-4">
      <h2 class="text-lg font-semibold text-white mb-3">Lint</h2>
      <% result = elem(@result, 1) %>

      <div :if={result.suggestions == [] && result.warnings == [] && result.errors == []}
        class="text-emerald-400 text-sm">
        No issues found
      </div>

      <div :for={s <- result.suggestions} class="text-blue-400 text-sm mb-1">
        <span class="font-mono text-blue-500">[{s.rule}]</span> {s.message}
      </div>

      <div :for={w <- result.warnings} class="text-yellow-400 text-sm mb-1">
        <span class="font-mono text-yellow-500">[{w.rule}]</span> {w.message}
      </div>

      <div :for={e <- result.errors} class="text-red-400 text-sm mb-1">
        <span class="font-mono text-red-500">[{e.rule}]</span> {e.message}
      </div>
    </div>
    """
  end
end
