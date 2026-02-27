defmodule PhoenixDatastar.RouterTest do
  @moduledoc """
  Tests for PhoenixDatastar.Router macros.

  The router module provides two main macros:
  - `datastar_session/3` - Groups routes under shared session configuration
  - `datastar/3` - Defines routes for a PhoenixDatastar view

  At compile time, these macros:
  - Register routes in `@phoenix_datastar_routes` module attribute
  - Generate `__phoenix_datastar_routes__/0` via `@before_compile`
  - Create GET routes for initial page loads (via PageController)
  - Create POST routes for events (via PhoenixDatastar.Plug)
  """
  use ExUnit.Case, async: true

  # =============================================================================
  # Test View Modules
  # =============================================================================

  defmodule StatelessView do
    use PhoenixDatastar

    @impl PhoenixDatastar
    def mount(_params, _session, socket), do: {:ok, socket}

    @impl PhoenixDatastar
    def render(_assigns), do: {:safe, "<div>Stateless</div>"}
  end

  defmodule LiveView do
    use PhoenixDatastar, :live

    @impl PhoenixDatastar
    def mount(_params, _session, socket), do: {:ok, socket}

    @impl PhoenixDatastar
    def render(_assigns), do: {:safe, "<div>Live</div>"}
  end

  defmodule DashboardView do
    use PhoenixDatastar, :live

    @impl PhoenixDatastar
    def mount(_params, _session, socket), do: {:ok, socket}

    @impl PhoenixDatastar
    def render(_assigns), do: {:safe, "<div>Dashboard</div>"}
  end

  defmodule SettingsView do
    use PhoenixDatastar, :live

    @impl PhoenixDatastar
    def mount(_params, _session, socket), do: {:ok, socket}

    @impl PhoenixDatastar
    def render(_assigns), do: {:safe, "<div>Settings</div>"}
  end

  defmodule UserShowView do
    use PhoenixDatastar, :live

    @impl PhoenixDatastar
    def mount(_params, _session, socket), do: {:ok, socket}

    @impl PhoenixDatastar
    def render(_assigns), do: {:safe, "<div>User</div>"}
  end

  defmodule HomeView do
    use PhoenixDatastar, :live

    @impl PhoenixDatastar
    def mount(_params, _session, socket), do: {:ok, socket}

    @impl PhoenixDatastar
    def render(_assigns), do: {:safe, "<div>Home</div>"}
  end

  # Custom HTML module for testing
  defmodule CustomHTML do
    use Phoenix.Component

    def mount(assigns) do
      ~H"<div data-custom><%= @inner_html %></div>"
    end
  end

  # Fake guard module for testing
  defmodule TestGuard do
    def authorized?(_conn), do: true
  end

  # =============================================================================
  # Test Routers
  # =============================================================================

  defmodule BasicRouter do
    @moduledoc "Router with basic datastar routes outside any session"
    use Phoenix.Router
    import PhoenixDatastar.Router

    scope "/" do
      datastar("/counter", StatelessView)
      datastar("/live", LiveView)
    end
  end

  defmodule SessionRouter do
    @moduledoc "Router with datastar_session blocks"
    use Phoenix.Router
    import PhoenixDatastar.Router

    scope "/" do
      datastar_session :dashboard do
        datastar("/dashboard", DashboardView)
        datastar("/dashboard/settings", SettingsView)
      end

      datastar_session :users, root_selector: "#users-container" do
        datastar("/users/:id", UserShowView)
      end
    end
  end

  defmodule SessionWithOptionsRouter do
    @moduledoc "Router with all session options"
    use Phoenix.Router
    import PhoenixDatastar.Router

    scope "/" do
      datastar_session :admin,
        root_selector: "#admin-root",
        stream_guard: {TestGuard, :authorized?},
        nav_guard: {TestGuard, :authorized?} do
        datastar("/admin", DashboardView)
      end
    end
  end

  defmodule NavGuardDefaultsRouter do
    @moduledoc "Router testing nav_guard defaulting to stream_guard"
    use Phoenix.Router
    import PhoenixDatastar.Router

    scope "/" do
      datastar_session :protected, stream_guard: {TestGuard, :authorized?} do
        datastar("/protected", DashboardView)
      end
    end
  end

  defmodule HtmlModuleRouter do
    @moduledoc "Router with custom html_module option"
    use Phoenix.Router
    import PhoenixDatastar.Router

    scope "/" do
      datastar_session :custom do
        datastar("/custom", DashboardView, html_module: CustomHTML)
      end
    end
  end

  defmodule ScopedRouter do
    @moduledoc "Router with nested Phoenix scopes"
    use Phoenix.Router
    import PhoenixDatastar.Router

    scope "/api/v1", as: :api_v1 do
      datastar_session :api do
        datastar("/dashboard", DashboardView)
      end
    end

    scope "/admin" do
      scope "/users" do
        datastar_session :admin_users do
          datastar("/:id", UserShowView)
        end
      end
    end
  end

  defmodule RootPathRouter do
    @moduledoc "Router with root path route"
    use Phoenix.Router
    import PhoenixDatastar.Router

    scope "/" do
      datastar_session :home do
        datastar("/", HomeView)
      end
    end
  end

  defmodule MixedRouter do
    @moduledoc "Router with both datastar and regular Phoenix routes"
    use Phoenix.Router
    import PhoenixDatastar.Router

    scope "/" do
      datastar_session :main do
        datastar("/counter", StatelessView)
      end

      # Regular Phoenix route - not a datastar route
      get("/health", PhoenixDatastar.PageController, :mount)
    end
  end

  defmodule NestedSessionRouter do
    @moduledoc "Router testing session restoration after nested blocks"
    use Phoenix.Router
    import PhoenixDatastar.Router

    scope "/" do
      datastar_session :outer, root_selector: "#outer" do
        datastar("/outer", DashboardView)

        datastar_session :inner, root_selector: "#inner" do
          datastar("/inner", SettingsView)
        end

        # This should use :outer session again
        datastar("/outer-again", LiveView)
      end
    end
  end

  defmodule NoDatastarRouter do
    @moduledoc "Router without any datastar routes"
    use Phoenix.Router

    scope "/" do
      get("/health", PhoenixDatastar.PageController, :mount)
    end
  end

  # =============================================================================
  # Tests: __phoenix_datastar_routes__/0 generation
  # =============================================================================

  describe "__phoenix_datastar_routes__/0" do
    test "is generated for routers using datastar macro" do
      assert function_exported?(BasicRouter, :__phoenix_datastar_routes__, 0)
      assert function_exported?(SessionRouter, :__phoenix_datastar_routes__, 0)
    end

    test "is not generated for routers without datastar macro" do
      refute function_exported?(NoDatastarRouter, :__phoenix_datastar_routes__, 0)
    end

    test "returns list of route metadata maps" do
      routes = BasicRouter.__phoenix_datastar_routes__()

      assert is_list(routes)
      assert length(routes) == 2

      # Routes should be in definition order (reversed during accumulation)
      [counter_route, live_route] = routes

      assert counter_route.path == "/counter"
      assert counter_route.view == StatelessView

      assert live_route.path == "/live"
      assert live_route.view == LiveView
    end
  end

  # =============================================================================
  # Tests: datastar/3 macro - route generation
  # =============================================================================

  describe "datastar/3 route generation" do
    test "generates GET route for page mount" do
      routes = Phoenix.Router.routes(BasicRouter)

      get_routes =
        Enum.filter(routes, fn route ->
          route.verb == :get and route.plug == PhoenixDatastar.PageController
        end)

      assert length(get_routes) == 2

      counter_route = Enum.find(get_routes, &(&1.path == "/counter"))
      assert counter_route
      assert counter_route.plug_opts == :mount
    end

    test "generates POST route for events" do
      routes = Phoenix.Router.routes(BasicRouter)

      post_routes =
        Enum.filter(routes, fn route ->
          route.verb == :post and route.plug == PhoenixDatastar.Plug
        end)

      assert length(post_routes) == 2

      counter_event_route = Enum.find(post_routes, &(&1.path == "/counter/_event/:event"))
      assert counter_event_route
      assert counter_event_route.plug_opts == [view: StatelessView]
    end

    test "route metadata includes view and path" do
      # The private metadata is set on routes but not exposed via Phoenix.Router.routes/1
      # Instead, we verify via __phoenix_datastar_routes__/0 which stores the same data
      routes = BasicRouter.__phoenix_datastar_routes__()

      counter_route = Enum.find(routes, &(&1.path == "/counter"))
      assert counter_route.view == StatelessView
      assert counter_route.path == "/counter"
    end
  end

  # =============================================================================
  # Tests: datastar/3 macro - options
  # =============================================================================

  describe "datastar/3 options" do
    test "passes html_module to route metadata" do
      routes = HtmlModuleRouter.__phoenix_datastar_routes__()
      [route] = routes

      assert route.html_module == CustomHTML
    end

    test "html_module defaults to nil when not specified" do
      routes = BasicRouter.__phoenix_datastar_routes__()
      [counter_route | _] = routes

      assert counter_route.html_module == nil
    end
  end

  # =============================================================================
  # Tests: datastar_session/3 macro
  # =============================================================================

  describe "datastar_session/3 session configuration" do
    test "sets session_name on contained routes" do
      routes = SessionRouter.__phoenix_datastar_routes__()

      dashboard_route = Enum.find(routes, &(&1.path == "/dashboard"))
      assert dashboard_route.session_name == :dashboard

      users_route = Enum.find(routes, &(&1.path == "/users/:id"))
      assert users_route.session_name == :users
    end

    test "sets root_selector option" do
      routes = SessionRouter.__phoenix_datastar_routes__()

      users_route = Enum.find(routes, &(&1.path == "/users/:id"))
      assert users_route.root_selector == "#users-container"
    end

    test "root_selector defaults to #app" do
      routes = SessionRouter.__phoenix_datastar_routes__()

      dashboard_route = Enum.find(routes, &(&1.path == "/dashboard"))
      assert dashboard_route.root_selector == "#app"
    end

    test "sets stream_guard option" do
      routes = SessionWithOptionsRouter.__phoenix_datastar_routes__()
      [route] = routes

      assert route.stream_guard == {TestGuard, :authorized?}
    end

    test "sets nav_guard option" do
      routes = SessionWithOptionsRouter.__phoenix_datastar_routes__()
      [route] = routes

      assert route.nav_guard == {TestGuard, :authorized?}
    end

    test "nav_guard defaults to stream_guard when not specified" do
      routes = NavGuardDefaultsRouter.__phoenix_datastar_routes__()
      [route] = routes

      assert route.stream_guard == {TestGuard, :authorized?}
      assert route.nav_guard == {TestGuard, :authorized?}
    end

    test "guards default to nil when not specified" do
      routes = BasicRouter.__phoenix_datastar_routes__()
      [route | _] = routes

      assert route.stream_guard == nil
      assert route.nav_guard == nil
    end
  end

  # =============================================================================
  # Tests: Default session (outside datastar_session block)
  # =============================================================================

  describe "default session (outside datastar_session)" do
    test "uses :default as session_name" do
      routes = BasicRouter.__phoenix_datastar_routes__()

      Enum.each(routes, fn route ->
        assert route.session_name == :default
      end)
    end

    test "uses #app as default root_selector" do
      routes = BasicRouter.__phoenix_datastar_routes__()

      Enum.each(routes, fn route ->
        assert route.root_selector == "#app"
      end)
    end

    test "sets guards to nil" do
      routes = BasicRouter.__phoenix_datastar_routes__()

      Enum.each(routes, fn route ->
        assert route.stream_guard == nil
        assert route.nav_guard == nil
      end)
    end
  end

  # =============================================================================
  # Tests: Phoenix scope integration
  # =============================================================================

  describe "Phoenix scope integration" do
    test "prepends scope path to route paths" do
      routes = ScopedRouter.__phoenix_datastar_routes__()

      api_route = Enum.find(routes, &(&1.session_name == :api))
      assert api_route.path == "/api/v1/dashboard"
    end

    test "handles nested scopes" do
      routes = ScopedRouter.__phoenix_datastar_routes__()

      admin_route = Enum.find(routes, &(&1.session_name == :admin_users))
      assert admin_route.path == "/admin/users/:id"
    end

    test "root path generates correct routes" do
      routes = RootPathRouter.__phoenix_datastar_routes__()
      [route] = routes

      assert route.path == "/"
    end

    test "root path event route doesn't have double slashes" do
      phoenix_routes = Phoenix.Router.routes(RootPathRouter)

      event_route =
        Enum.find(phoenix_routes, fn r ->
          r.verb == :post and r.plug == PhoenixDatastar.Plug
        end)

      assert event_route.path == "/_event/:event"
      refute event_route.path =~ "//"
    end
  end

  # =============================================================================
  # Tests: Nested datastar_session blocks
  # =============================================================================

  describe "nested datastar_session blocks" do
    test "inner session overrides outer session" do
      routes = NestedSessionRouter.__phoenix_datastar_routes__()

      inner_route = Enum.find(routes, &(&1.path == "/inner"))
      assert inner_route.session_name == :inner
      assert inner_route.root_selector == "#inner"
    end

    test "outer session is restored after inner block" do
      routes = NestedSessionRouter.__phoenix_datastar_routes__()

      outer_again_route = Enum.find(routes, &(&1.path == "/outer-again"))
      assert outer_again_route.session_name == :outer
      assert outer_again_route.root_selector == "#outer"
    end

    test "outer route before nesting has correct session" do
      routes = NestedSessionRouter.__phoenix_datastar_routes__()

      outer_route = Enum.find(routes, &(&1.path == "/outer"))
      assert outer_route.session_name == :outer
      assert outer_route.root_selector == "#outer"
    end
  end

  # =============================================================================
  # Tests: Route metadata structure
  # =============================================================================

  describe "route metadata structure" do
    test "includes all required fields" do
      routes = SessionWithOptionsRouter.__phoenix_datastar_routes__()
      [route] = routes

      assert Map.has_key?(route, :view)
      assert Map.has_key?(route, :path)
      assert Map.has_key?(route, :html_module)
      assert Map.has_key?(route, :session_name)
      assert Map.has_key?(route, :stream_guard)
      assert Map.has_key?(route, :nav_guard)
      assert Map.has_key?(route, :root_selector)
    end

    test "view is fully qualified module name" do
      routes = BasicRouter.__phoenix_datastar_routes__()
      [counter_route | _] = routes

      # View should be the full module path
      assert counter_route.view == PhoenixDatastar.RouterTest.StatelessView
    end
  end

  # =============================================================================
  # Tests: Mixed routes (datastar + regular Phoenix routes)
  # =============================================================================

  describe "mixed routes" do
    test "only datastar routes are in __phoenix_datastar_routes__" do
      routes = MixedRouter.__phoenix_datastar_routes__()

      assert length(routes) == 1
      assert hd(routes).path == "/counter"
    end

    test "regular Phoenix routes still work" do
      phoenix_routes = Phoenix.Router.routes(MixedRouter)

      health_route =
        Enum.find(phoenix_routes, fn r ->
          r.path == "/health" and r.verb == :get
        end)

      assert health_route
      assert health_route.plug == PhoenixDatastar.PageController
    end
  end

  # =============================================================================
  # Tests: Route ordering
  # =============================================================================

  describe "route ordering" do
    test "routes are returned in definition order" do
      routes = SessionRouter.__phoenix_datastar_routes__()

      paths = Enum.map(routes, & &1.path)

      # Routes should be in the order they were defined
      assert paths == [
               "/dashboard",
               "/dashboard/settings",
               "/users/:id"
             ]
    end
  end

  # =============================================================================
  # Tests: Dynamic path parameters
  # =============================================================================

  describe "dynamic path parameters" do
    test "path pattern is stored with parameter placeholders" do
      routes = SessionRouter.__phoenix_datastar_routes__()

      users_route = Enum.find(routes, &(&1.path == "/users/:id"))
      assert users_route.path == "/users/:id"
    end

    test "nested dynamic segments are preserved" do
      routes = ScopedRouter.__phoenix_datastar_routes__()

      admin_route = Enum.find(routes, &(&1.session_name == :admin_users))
      assert admin_route.path == "/admin/users/:id"
    end
  end

  # =============================================================================
  # Tests: Phoenix route plug configuration
  # =============================================================================

  describe "Phoenix route plug configuration" do
    test "GET route uses PageController with :mount action" do
      phoenix_routes = Phoenix.Router.routes(SessionWithOptionsRouter)

      get_route =
        Enum.find(phoenix_routes, fn r ->
          r.verb == :get and r.path == "/admin"
        end)

      assert get_route.plug == PhoenixDatastar.PageController
      assert get_route.plug_opts == :mount
    end

    test "POST event route includes view in plug_opts" do
      phoenix_routes = Phoenix.Router.routes(BasicRouter)

      post_route =
        Enum.find(phoenix_routes, fn r ->
          r.verb == :post and r.path == "/counter/_event/:event"
        end)

      assert post_route.plug == PhoenixDatastar.Plug
      assert post_route.plug_opts == [view: StatelessView]
    end

    test "all session metadata is stored in __phoenix_datastar_routes__" do
      # Phoenix.Router.routes/1 doesn't expose private metadata,
      # but our __phoenix_datastar_routes__/0 function stores all session info
      routes = SessionWithOptionsRouter.__phoenix_datastar_routes__()
      [route] = routes

      assert route.view == DashboardView
      assert route.path == "/admin"
      assert route.session_name == :admin
      assert route.root_selector == "#admin-root"
      assert route.stream_guard == {TestGuard, :authorized?}
      assert route.nav_guard == {TestGuard, :authorized?}
    end
  end
end
