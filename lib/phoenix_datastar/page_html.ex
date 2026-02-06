defmodule PhoenixDatastar.PageHTML do
  @moduledoc """
  Minimal HTML component for rendering Datastar view content.

  Renders `@inner_html` directly without any wrapper elements.
  Signal injection (data-signals, data-init__once) is handled by the root layout.
  """
  use Phoenix.Component

  def mount(assigns) do
    ~H"""
    {@inner_html}
    """
  end
end
