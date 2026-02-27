defmodule PhoenixDatastar.NavPlugTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Plug.Conn

  alias PhoenixDatastar.NavPlug
  alias PhoenixDatastar.Server
  alias PhoenixDatastar.StreamToken

  defmodule TestEndpoint do
    def config(:secret_key_base), do: String.duplicate("a", 64)
  end

  defmodule LiveHomeStar do
    use PhoenixDatastar, :live

    @impl PhoenixDatastar
    def mount(_params, _session, socket) do
      {:ok, PhoenixDatastar.Socket.assign(socket, :page, "home")}
    end

    @impl PhoenixDatastar
    def render(assigns) do
      {:safe, "<div>Home: #{assigns[:page]}</div>"}
    end
  end

  defmodule LiveDashboardStar do
    use PhoenixDatastar, :live

    @impl PhoenixDatastar
    def mount(params, _session, socket) do
      {:ok, PhoenixDatastar.Socket.assign(socket, :params, params)}
    end

    @impl PhoenixDatastar
    def render(assigns) do
      {:safe, "<div>Dashboard: #{inspect(assigns[:params])}</div>"}
    end
  end

  defmodule LiveSettingsStar do
    use PhoenixDatastar, :live

    @impl PhoenixDatastar
    def mount(_params, _session, socket), do: {:ok, socket}

    @impl PhoenixDatastar
    def render(_assigns), do: {:safe, "<div>Settings</div>"}
  end

  defmodule StatelessView do
    use PhoenixDatastar

    @impl PhoenixDatastar
    def mount(_params, _session, socket), do: {:ok, socket}

    @impl PhoenixDatastar
    def render(_assigns), do: {:safe, "<div>Stateless</div>"}
  end

  defmodule TestRouter do
    use Phoenix.Router
    import PhoenixDatastar.Router

    scope "/" do
      datastar_session :main, root_selector: "#main-app" do
        datastar("/", LiveHomeStar)
        datastar("/dashboard", LiveDashboardStar)
        datastar("/dashboard/:id", LiveDashboardStar)
      end

      datastar_session :settings do
        datastar("/settings", LiveSettingsStar)
      end

      datastar_session :stateless_session do
        datastar("/stateless", StatelessView)
      end

      Phoenix.Router.get("/health", PhoenixDatastar.PageController, :mount)
    end
  end

  setup_all do
    case Elixir.Registry.start_link(keys: :unique, name: PhoenixDatastar.Registry) do
      {:ok, pid} -> {:ok, registry_pid: pid}
      {:error, {:already_started, pid}} -> {:ok, registry_pid: pid}
    end
  end

  setup do
    session_id = "nav-test-#{System.unique_integer([:positive])}"

    on_exit(fn ->
      try do
        case Elixir.Registry.lookup(PhoenixDatastar.Registry, session_id) do
          [{pid, _}] when is_pid(pid) ->
            if Process.alive?(pid), do: GenServer.stop(pid, :normal, 100)

          _ ->
            :ok
        end
      catch
        :exit, _ -> :ok
      end
    end)

    %{session_id: session_id}
  end

  defp build_nav_conn(params) do
    build_conn(:post, "/__datastar/nav", params)
    |> put_private(:phoenix_endpoint, TestEndpoint)
    |> put_private(:phoenix_router, TestRouter)
  end

  defp sign_token(conn, payload) do
    StreamToken.sign(conn, payload)
  end

  describe "call/2 - fallback scenarios" do
    test "falls back to hard reload when token is invalid" do
      conn = build_nav_conn(%{"_ds_to" => "/outside", "token" => "invalid"})

      conn = NavPlug.call(conn, [])

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["text/event-stream; charset=utf-8"]
      assert conn.resp_body =~ "window.location='/outside'"
    end

    test "falls back when _ds_to is missing" do
      conn = build_nav_conn(%{"token" => "some_token"})

      conn = NavPlug.call(conn, [])

      assert conn.status == 200
      assert conn.resp_body =~ "window.location='/'"
    end

    test "falls back when target path does not match any datastar route" do
      payload = %{"session_id" => "test-123", "session_name" => "main"}
      conn = build_nav_conn(%{"_ds_to" => "/nonexistent/path"})
      token = sign_token(conn, payload)
      conn = Map.put(conn, :params, Map.put(conn.params, "token", token))

      conn = NavPlug.call(conn, [])

      assert conn.resp_body =~ "window.location='/nonexistent/path'"
    end

    test "falls back when session_name does not match target route" do
      payload = %{"session_id" => "test-123", "session_name" => "wrong_session"}
      conn = build_nav_conn(%{"_ds_to" => "/dashboard"})
      token = sign_token(conn, payload)
      conn = Map.put(conn, :params, Map.put(conn.params, "token", token))

      conn = NavPlug.call(conn, [])

      assert conn.resp_body =~ "window.location='/dashboard'"
    end

    test "falls back when target view is not a live view" do
      payload = %{"session_id" => "test-123", "session_name" => "stateless_session"}
      conn = build_nav_conn(%{"_ds_to" => "/stateless"})
      token = sign_token(conn, payload)
      conn = Map.put(conn, :params, Map.put(conn.params, "token", token))

      conn = NavPlug.call(conn, [])

      assert conn.resp_body =~ "window.location='/stateless'"
    end
  end

  describe "call/2 - successful soft navigation" do
    test "returns nav-ack SSE response and uses root_selector from route", %{session_id: session_id} do
      {:ok, _pid} = Server.ensure_started(LiveHomeStar, session_id, %{}, %{}, "/")
      :ok = Server.subscribe(session_id)

      payload = %{"session_id" => session_id, "session_name" => :main}
      conn = build_nav_conn(%{"_ds_to" => "/dashboard"})
      token = sign_token(conn, payload)
      conn = Map.put(conn, :params, Map.put(conn.params, "token", token))

      conn = NavPlug.call(conn, [])

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["text/event-stream; charset=utf-8"]
      assert conn.resp_body == ": nav-ack\n\n"

      assert_receive {:datastar_events, events}, 1000
      [{:patch, selector, _html, _opts}, {:script, script, _}] = events
      assert selector == "#main-app"
      assert script =~ "history.pushState"
    end

    test "respects _ds_mode=replace parameter", %{session_id: session_id} do
      {:ok, _pid} = Server.ensure_started(LiveHomeStar, session_id, %{}, %{}, "/")
      :ok = Server.subscribe(session_id)

      payload = %{"session_id" => session_id, "session_name" => :main}
      conn = build_nav_conn(%{"_ds_to" => "/dashboard", "_ds_mode" => "replace"})
      token = sign_token(conn, payload)
      conn = Map.put(conn, :params, Map.put(conn.params, "token", token))

      NavPlug.call(conn, [])

      assert_receive {:datastar_events, events}, 1000
      [{:patch, _selector, _html, _opts}, {:script, script, _}] = events
      assert script =~ "history.replaceState"
    end

    test "issues new nav_token in framework_signals", %{session_id: session_id} do
      {:ok, _pid} = Server.ensure_started(LiveHomeStar, session_id, %{}, %{}, "/")
      :ok = Server.subscribe(session_id)

      payload = %{"session_id" => session_id, "session_name" => :main}
      conn = build_nav_conn(%{"_ds_to" => "/dashboard"})
      token = sign_token(conn, payload)
      conn = Map.put(conn, :params, Map.put(conn.params, "token", token))

      NavPlug.call(conn, [])

      assert_receive {:datastar_signals, signals}, 1000
      assert is_binary(signals.nav_token)
      assert signals.event_path == "/dashboard/_event"
      assert signals.nav_path == "/__datastar/nav"
      assert signals.session_id == session_id

      assert {:ok, new_payload} = StreamToken.verify(conn, signals.nav_token)
      assert new_payload["session_id"] == session_id
    end

    test "navigates to route with path parameters", %{session_id: session_id} do
      {:ok, _pid} = Server.ensure_started(LiveHomeStar, session_id, %{}, %{}, "/")
      :ok = Server.subscribe(session_id)

      payload = %{"session_id" => session_id, "session_name" => :main}
      conn = build_nav_conn(%{"_ds_to" => "/dashboard/123"})
      token = sign_token(conn, payload)
      conn = Map.put(conn, :params, Map.put(conn.params, "token", token))

      conn = NavPlug.call(conn, [])

      assert conn.resp_body == ": nav-ack\n\n"
    end

    test "defaults root_selector to #app when not specified", %{session_id: session_id} do
      {:ok, _pid} = Server.ensure_started(LiveSettingsStar, session_id, %{}, %{}, "/settings")
      :ok = Server.subscribe(session_id)

      payload = %{"session_id" => session_id, "session_name" => :settings}
      conn = build_nav_conn(%{"_ds_to" => "/settings"})
      token = sign_token(conn, payload)
      conn = Map.put(conn, :params, Map.put(conn.params, "token", token))

      NavPlug.call(conn, [])

      assert_receive {:datastar_events, events}, 1000
      [{:patch, selector, _html, _opts}, _] = events
      assert selector == "#app"
    end
  end
end
