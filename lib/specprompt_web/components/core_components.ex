defmodule SpecPromptWeb.CoreComponents do
  @moduledoc """
  Provides core UI components.
  """
  use Phoenix.Component

  attr(:flash, :map, required: true)
  attr(:kind, :atom, values: [:info, :error], default: :info)

  def flash_group(assigns) do
    ~H"""
    <.flash :if={Phoenix.Flash.get(@flash, :info)} kind={:info} flash={@flash} />
    <.flash :if={Phoenix.Flash.get(@flash, :error)} kind={:error} flash={@flash} />
    """
  end

  attr(:kind, :atom, required: true)
  attr(:flash, :map, required: true)
  attr(:rest, :global)

  def flash(assigns) do
    ~H"""
    <div
      :if={msg = Phoenix.Flash.get(@flash, @kind)}
      class={[
        "mb-4 rounded-lg p-4 text-sm",
        @kind == :info && "bg-blue-900/50 text-blue-300 border border-blue-800",
        @kind == :error && "bg-red-900/50 text-red-300 border border-red-800"
      ]}
      {@rest}
    >
      {msg}
    </div>
    """
  end
end
