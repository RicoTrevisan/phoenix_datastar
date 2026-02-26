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

  defmodule TestRouter do
    use Phoenix.Router
    import PhoenixDatastar.Router

    scope "/" do
      datastar_session :dashboard, root_selector: "#dashboard-root" do
        datastar("/dashboard", DashboardStar)
        datastar("/dashboard/orgs", DashboardOrgsStar)
      end

      get("/health", PhoenixDatastar.PageController, :mount)
    end
  end

  test "matches datastar routes and returns session metadata" do
    assert %{datastar: datastar} =
             RouteRegistry.match(TestRouter, "GET", "/dashboard", "localhost")

    assert datastar.session_name == :dashboard
    assert datastar.root_selector == "#dashboard-root"
  end

  test "returns nil for non-datastar routes" do
    assert RouteRegistry.match(TestRouter, "GET", "/health", "localhost") == nil
  end
end
