defmodule PhoenixDatastar.Router do
  @moduledoc """
  Router macros for PhoenixDatastar.

  ## Usage

      import PhoenixDatastar.Router

      # Global event handler (call once, outside scopes)
      datastar_events()

      scope "/", MyAppWeb do
        pipe_through :browser

        # Stateless view (use PhoenixDatastar)
        datastar "/counter", CounterStar

        # Live view (use PhoenixDatastar, :live)
        datastar "/multiplayer", MultiplayerStar

        # With custom HTML module
        datastar "/custom", CustomStar, html_module: MyAppWeb.CustomHTML
      end

  `datastar_events/1` generates:
    - POST /_datastar/event/:event - Global event handler for all views

  `datastar/3` generates per-view routes:
    - GET /counter - renders the initial page
    - GET /counter/stream - SSE stream endpoint (live views only)

  ## Configuration

  Set a default HTML module in your config:

      config :phoenix_datastar, :html_module, MyAppWeb.DatastarHTML

  Or pass `html_module` option per-route to override.
  """

  @doc """
  Defines the global event route for PhoenixDatastar.

  This should be called once in your router, typically at the top level outside of scopes,
  or in a scope with appropriate pipelines (e.g., CSRF protection).

  ## Options

    * `path` - The base path for the event endpoint. Defaults to `"/_datastar"`.

  ## Example

      import PhoenixDatastar.Router

      datastar_events()

      scope "/", MyAppWeb do
        pipe_through :browser
        datastar "/counter", CounterStar
      end

  This generates:
    - POST /_datastar/event/:event - Global event handler
  """
  defmacro datastar_events(path \\ "/_datastar") do
    quote do
      post("#{unquote(path)}/event/:event", PhoenixDatastar.Plug, [], alias: false)
    end
  end

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

      # Apply scope alias only if view isn't already fully qualified.
      # Module atoms like CounterSse become "Elixir.CounterSse" (1 dot),
      # while LiveStarTestWeb.CounterSse becomes "Elixir.LiveStarTestWeb.CounterSse" (2+ dots).
      # Only apply scoped_alias to single-segment module names.
      view =
        case view |> Atom.to_string() |> String.split(".") do
          ["Elixir", _single_segment] ->
            Phoenix.Router.scoped_alias(__MODULE__, view)

          _already_qualified ->
            view
        end

      # Get full path including scope prefix (e.g., "/" in scope "/sse" becomes "/sse")
      full_path = Phoenix.Router.scoped_path(__MODULE__, path)

      # Initial page load
      get(path, PhoenixDatastar.PageController, :mount,
        private: %{datastar: %{view: view, path: full_path, html_module: html_module}},
        alias: false
      )

      # SSE stream connection
      get("#{path}/stream", PhoenixDatastar.Plug, [view: view], alias: false)
    end
  end
end
