defmodule PhoenixDatastar.DefaultHTML do
  @moduledoc """
  Built-in HTML template for rendering the PhoenixDatastar mount wrapper.

  This module provides the default template that wraps view content with
  the necessary Datastar signals and SSE stream initialization.

  It is used automatically when no custom HTML module is configured.
  To override, create your own module and configure it:

      config :phoenix_datastar, :html_module, MyAppWeb.DatastarHTML

  Or per-route:

      datastar "/path", MyView, html_module: MyAppWeb.DatastarHTML

  ## Custom Module Example

      defmodule MyAppWeb.DatastarHTML do
        use Phoenix.Component

        def mount(assigns) do
          ~H\"\"\"
          <div
            id="my-app"
            class="custom-wrapper"
            data-signals={Jason.encode!(Map.put(@initial_signals, :session_id, @session_id))}
            data-init__once={@stream_path && "@get('\#{@stream_path}', {openWhenHidden: true})"}
          >
            {@inner_html}
          </div>
          \"\"\"
        end
      end
  """

  use Phoenix.Component

  @doc """
  Renders the mount template wrapping the view's content.

  ## Assigns

    * `@session_id` - The unique session identifier
    * `@stream_path` - The SSE stream path (nil for stateless views)
    * `@initial_signals` - Map of user-defined assigns from `mount/3` to initialize as Datastar signals
    * `@inner_html` - The rendered view content
  """
  def mount(assigns) do
    ~H"""
    <div
      data-signals={Jason.encode!(Map.put(@initial_signals, :session_id, @session_id))}
      data-init__once={@stream_path && "@get('#{@stream_path}', {openWhenHidden: true})"}
    >
      {@inner_html}
    </div>
    """
  end
end
