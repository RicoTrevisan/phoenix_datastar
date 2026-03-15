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
            data-signals={
              Jason.encode!(
                Map.merge(@initial_signals, %{
                  session_id: @session_id,
                  event_path: @event_path,
                  nav_path: @nav_path,
                  nav_token: @nav_token
                })
              )
            }
            data-init={@stream_path && "@post('\#{@stream_path}', {retryMaxCount: Infinity})"}
            data-on:online__window={@stream_path && "@post('\#{@stream_path}', {retryMaxCount: Infinity})"}
          >
            {@inner_html}
          </div>
          \"\"\"
        end
      end

  All four framework signals (`session_id`, `event_path`, `nav_path`, `nav_token`)
  must be included in `data-signals` for events and soft navigation to work.
  """

  use Phoenix.Component

  @doc """
  Renders the mount template wrapping the view's content.

  ## Assigns

    * `@session_id` - The unique session identifier
    * `@stream_path` - The SSE stream path (nil for stateless views)
    * `@event_path` - The event POST path
    * `@nav_path` - Soft navigation endpoint path
    * `@nav_token` - Signed token for stream/nav authorization
    * `@initial_signals` - Map of signals set via `put_signal` in `mount/3`
    * `@inner_html` - The rendered view content
  """
  @spec mount(map()) :: Phoenix.LiveView.Rendered.t()
  def mount(assigns) do
    ~H"""
    <div
      id="app"
      data-signals={
        Jason.encode!(
          Map.merge(@initial_signals, %{
            session_id: @session_id,
            event_path: @event_path,
            nav_path: @nav_path,
            nav_token: @nav_token
          })
        )
      }
      data-init={@stream_path && "@post('#{@stream_path}', {retryMaxCount: Infinity})"}
      data-on:online__window={@stream_path && "@post('#{@stream_path}', {retryMaxCount: Infinity})"}
    >
      {@inner_html}
    </div>
    """
  end
end
