defmodule PhoenixDatastar.Router do
  @moduledoc """
  Router macros for PhoenixDatastar.

  ## Usage

      import PhoenixDatastar.Router

      scope "/", MyAppWeb do
        pipe_through :browser

        # Stateless view (use PhoenixDatastar)
        datastar "/counter", CounterStar

        # Live view (use PhoenixDatastar, :live)
        datastar "/multiplayer", MultiplayerStar

        # With custom HTML module
        datastar "/custom", CustomStar, html_module: MyAppWeb.CustomHTML
      end

  For stateless views, this generates two routes:
    - GET /counter - renders the initial page
    - POST /counter/event/:event - handles events, returns signals

  For live views, this generates three routes:
    - GET /counter - renders the initial page and starts GenServer
    - GET /counter/stream - SSE stream endpoint
    - POST /counter/event/:event - dispatches events to GenServer

  ## Configuration

  Set a default HTML module in your config:

      config :phoenix_datastar, :html_module, MyAppWeb.DatastarHTML

  Or pass `html_module` option per-route to override.
  """

  @doc """
  Defines routes for a PhoenixDatastar view.

  The macro auto-detects whether the view is stateless (`use PhoenixDatastar`) or
  live (`use PhoenixDatastar, :live`) and generates appropriate routes.

  ## Options

    * `:html_module` - The Phoenix HTML module to use for rendering the mount template.
      Defaults to `Application.get_env(:phoenix_datastar, :html_module)`.
  """
  defmacro datastar(path, view, opts \\ []) do
    quote bind_quoted: [path: path, view: view, opts: opts] do
      html_module = Keyword.get(opts, :html_module)

      # Initial page load
      get path, PhoenixDatastar.PageController, :mount,
        private: %{datastar: %{view: view, path: path, html_module: html_module}}

      # SSE stream connection
      get "#{path}/stream", PhoenixDatastar.Plug, view: view

      # Event handling
      post "#{path}/event/:event", PhoenixDatastar.Plug, view: view
    end
  end
end
