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

  `datastar/3` generates per-view routes:
    - GET /counter - renders the initial page
    - POST /counter/_event/:event - handles events
    - GET /counter/stream - SSE stream endpoint (live views only)

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
    # Expand at macro time in caller's context - this resolves any existing
    # aliases (like `alias MyApp.CounterSse` at top of router)
    view = Macro.expand_literals(view, %{__CALLER__ | function: {:datastar, 3}})
    opts = Macro.expand_literals(opts, %{__CALLER__ | function: {:datastar, 3}})

    quote bind_quoted: [path: path, view: view, opts: opts] do
      html_module = Keyword.get(opts, :html_module)

      # Apply scope alias to the view module, matching Phoenix convention for
      # controllers. Inside `scope "/", MyAppWeb`, module names like `CounterSse`
      # or `Home.DashboardSse` are relative and get prefixed with the scope alias.
      # If no scope alias is set, this is a no-op.
      view = Phoenix.Router.scoped_alias(__MODULE__, view)

      # Get full path including scope prefix (e.g., "/" in scope "/sse" becomes "/sse")
      full_path = Phoenix.Router.scoped_path(__MODULE__, path)

      # Initial page load (all views)
      get(path, PhoenixDatastar.PageController, :mount,
        private: %{datastar: %{view: view, path: full_path, html_module: html_module}},
        alias: false
      )

      # Per-page event endpoint (all views)
      # Use Path.join to handle root path "/" correctly (avoids "//")
      post(Path.join(path, "_event/:event"), PhoenixDatastar.Plug, [view: view], alias: false)

      # SSE stream endpoint (live views only)
      if PhoenixDatastar.live?(view) do
        get(Path.join(path, "stream"), PhoenixDatastar.Plug, [view: view], alias: false)
      end
    end
  end
end
