defmodule PhoenixDatastar.RouteRegistryTest do
  use ExUnit.Case, async: true

  alias PhoenixDatastar.RouteRegistry

  defmodule DashboardStar do
    use PhoenixDatastar, :live

    @impl PhoenixDatastar
    def mount(_params, _session, socket), do: {:ok, socket}

    @impl PhoenixDatastar
    def render(_assigns), do: "ok"
  end

  defmodule DashboardOrgsStar do
    use PhoenixDatastar, :live

    @impl PhoenixDatastar
    def mount(_params, _session, socket), do: {:ok, socket}

    @impl PhoenixDatastar
    def render(_assigns), do: "ok"
  end

  defmodule UserShowStar do
    use PhoenixDatastar, :live

    @impl PhoenixDatastar
    def mount(_params, _session, socket), do: {:ok, socket}

    @impl PhoenixDatastar
    def render(_assigns), do: "ok"
  end

  defmodule OrgUserStar do
    use PhoenixDatastar, :live

    @impl PhoenixDatastar
    def mount(_params, _session, socket), do: {:ok, socket}

    @impl PhoenixDatastar
    def render(_assigns), do: "ok"
  end

  defmodule HomeStar do
    use PhoenixDatastar, :live

    @impl PhoenixDatastar
    def mount(_params, _session, socket), do: {:ok, socket}

    @impl PhoenixDatastar
    def render(_assigns), do: "ok"
  end

  defmodule TestRouter do
    use Phoenix.Router
    import PhoenixDatastar.Router

    scope "/" do
      datastar_session :dashboard, root_selector: "#dashboard-root" do
        datastar("/dashboard", DashboardStar)
        datastar("/dashboard/orgs", DashboardOrgsStar)
      end

      datastar_session :users do
        datastar("/users/:id", UserShowStar)
        datastar("/orgs/:org_id/users/:user_id", OrgUserStar)
      end

      datastar_session :home do
        datastar("/", HomeStar)
      end

      get("/health", PhoenixDatastar.PageController, :mount)
    end
  end

  defmodule PlainRouter do
    use Phoenix.Router

    scope "/" do
      get("/health", PhoenixDatastar.PageController, :mount)
    end
  end

  describe "match/4" do
    test "matches datastar routes and returns session metadata" do
      assert %{datastar: datastar, path_params: path_params} =
               RouteRegistry.match(TestRouter, "GET", "/dashboard", "localhost")

      assert datastar.session_name == :dashboard
      assert datastar.root_selector == "#dashboard-root"
      assert datastar.view == DashboardStar
      assert datastar.path == "/dashboard"
      assert path_params == %{}
    end

    test "matches nested static paths" do
      assert %{datastar: datastar} =
               RouteRegistry.match(TestRouter, "GET", "/dashboard/orgs", "localhost")

      assert datastar.view == DashboardOrgsStar
    end

    test "returns nil for non-datastar and unregistered routes" do
      assert RouteRegistry.match(TestRouter, "GET", "/health", "localhost") == nil
      assert RouteRegistry.match(TestRouter, "GET", "/nonexistent", "localhost") == nil
    end

    test "extracts single path parameter" do
      assert %{datastar: datastar, path_params: path_params} =
               RouteRegistry.match(TestRouter, "GET", "/users/123", "localhost")

      assert datastar.view == UserShowStar
      assert path_params == %{"id" => "123"}
    end

    test "extracts multiple path parameters" do
      assert %{path_params: path_params} =
               RouteRegistry.match(TestRouter, "GET", "/orgs/acme/users/456", "localhost")

      assert path_params == %{"org_id" => "acme", "user_id" => "456"}
    end

    test "matches root path" do
      assert %{datastar: datastar} =
               RouteRegistry.match(TestRouter, "GET", "/", "localhost")

      assert datastar.session_name == :home
      assert datastar.view == HomeStar
    end

    test "does not match paths with different segment count" do
      assert RouteRegistry.match(TestRouter, "GET", "/users", "localhost") == nil
      assert RouteRegistry.match(TestRouter, "GET", "/users/123/extra", "localhost") == nil
    end

    test "returns nil for router without datastar routes" do
      assert RouteRegistry.match(PlainRouter, "GET", "/anything", "localhost") == nil
    end

    test "root_selector defaults to #app when not specified" do
      assert %{datastar: datastar} =
               RouteRegistry.match(TestRouter, "GET", "/users/123", "localhost")

      assert datastar.root_selector == "#app"
    end
  end

  describe "session_name/4" do
    test "returns session name for matching routes, nil otherwise" do
      assert RouteRegistry.session_name(TestRouter, "GET", "/dashboard", "localhost") == :dashboard
      assert RouteRegistry.session_name(TestRouter, "GET", "/users/123", "localhost") == :users
      assert RouteRegistry.session_name(TestRouter, "GET", "/health", "localhost") == nil
      assert RouteRegistry.session_name(PlainRouter, "GET", "/anything", "localhost") == nil
    end
  end
end
