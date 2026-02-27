defmodule PhoenixDatastar.Router do
  @moduledoc """
  Router macros for PhoenixDatastar.

  ## Usage

      import PhoenixDatastar.Router

      scope "/", MyAppWeb do
        pipe_through :browser

        datastar_session :default do
          datastar "/counter", CounterStar
        end
      end

  `datastar/3` generates per-view routes:
    - `GET /counter` — renders the initial page via `PhoenixDatastar.PageController`
    - `POST /counter/_event/:event` — handles events via `PhoenixDatastar.Plug`

  For live views, a global SSE stream endpoint (`PhoenixDatastar.StreamPlug`) and
  a navigation endpoint (`PhoenixDatastar.NavPlug`) must also be added to the router.
  See the README for the full setup.
  """

  @doc false
  defmacro __before_compile__(env) do
    routes =
      env.module
      |> Module.get_attribute(:phoenix_datastar_routes)
      |> List.wrap()
      |> Enum.reverse()

    quote do
      @doc false
      def __phoenix_datastar_routes__, do: unquote(Macro.escape(routes))
    end
  end

  @doc """
  Groups datastar routes under shared stream/navigation behavior.

  Routes within a `datastar_session` block are registered in the
  `PhoenixDatastar.RouteRegistry` for soft navigation matching. When a user
  navigates between views in the same session, the existing SSE connection
  is reused and the view is swapped in-place without a full page reload.

  Soft navigation only works between live views (`use PhoenixDatastar, :live`)
  within the same session. Stateless views always trigger a full page reload.

  ## Options

    * `:root_selector` - CSS selector for the container element patched during
      soft navigation. Defaults to `"#app"`.
    * `:stream_guard` - MFA tuple `{Module, :function}` stored as route metadata.
      Reserved for future use — not currently enforced by `StreamPlug` or `NavPlug`.
      Use pipeline plugs for authorization instead.
    * `:nav_guard` - MFA tuple `{Module, :function}` stored as route metadata.
      Defaults to `:stream_guard`. Reserved for future use — not currently enforced.
  """
  defmacro datastar_session(name, opts \\ [], do: block) do
    quote do
      opts = unquote(opts)

      session = %{
        name: unquote(name),
        stream_guard: Keyword.get(opts, :stream_guard),
        nav_guard: Keyword.get_lazy(opts, :nav_guard, fn -> Keyword.get(opts, :stream_guard) end),
        root_selector: Keyword.get(opts, :root_selector, "#app")
      }

      previous = Module.get_attribute(__MODULE__, :phoenix_datastar_current_session)
      Module.put_attribute(__MODULE__, :phoenix_datastar_current_session, session)

      try do
        unquote(block)
      after
        Module.put_attribute(__MODULE__, :phoenix_datastar_current_session, previous)
      end
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
    view = Macro.expand_literals(view, %{__CALLER__ | function: {:datastar, 3}})
    opts = Macro.expand_literals(opts, %{__CALLER__ | function: {:datastar, 3}})

    quote bind_quoted: [path: path, view: view, opts: opts] do
      if Module.get_attribute(__MODULE__, :phoenix_datastar_routes) == nil do
        Module.register_attribute(__MODULE__, :phoenix_datastar_routes, accumulate: true)
        @before_compile PhoenixDatastar.Router
      end

      html_module = Keyword.get(opts, :html_module)

      session =
        Module.get_attribute(__MODULE__, :phoenix_datastar_current_session) ||
          %{name: :default, stream_guard: nil, nav_guard: nil, root_selector: "#app"}

      view = Phoenix.Router.scoped_alias(__MODULE__, view)
      Code.ensure_compiled!(view)
      @external_resource view.__info__(:compile)[:source] |> List.to_string()

      full_path = Phoenix.Router.scoped_path(__MODULE__, path)

      datastar_private = %{
        view: view,
        path: full_path,
        html_module: html_module,
        session_name: session.name,
        stream_guard: session.stream_guard,
        nav_guard: session.nav_guard,
        root_selector: session.root_selector
      }

      @phoenix_datastar_routes datastar_private

      get(path, PhoenixDatastar.PageController, :mount,
        private: %{datastar: datastar_private},
        alias: false
      )

      post(Path.join(path, "_event/:event"), PhoenixDatastar.Plug, [view: view], alias: false)
    end
  end
end
