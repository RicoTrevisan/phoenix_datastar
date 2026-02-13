defmodule PhoenixDatastar.StatelessRenderingTest do
  use ExUnit.Case
  import Phoenix.ConnTest
  import Plug.Conn

  defmodule TestHTML do
    use Phoenix.Component

    def mount(assigns) do
      # Render stream path and event path so we can check them
      ~H"Stream: <%= @stream_path %> Event: <%= @event_path %>"
    end
  end

  defmodule TestHTMLWithSignals do
    use Phoenix.Component

    def mount(assigns) do
      ~H"Signals: <%= Jason.encode!(@initial_signals) %>"
    end
  end

  defmodule StatelessView do
    use PhoenixDatastar

    @impl PhoenixDatastar
    def mount(_params, _session, socket), do: {:ok, socket}

    @impl PhoenixDatastar
    def render(assigns), do: ~H"Hello"
  end

  defmodule StatelessViewWithSignals do
    use PhoenixDatastar

    @impl PhoenixDatastar
    def mount(_params, _session, socket) do
      {:ok, put_signal(socket, :count, 0)}
    end

    @impl PhoenixDatastar
    def handle_event("increment", params, socket) do
      count = params["count"] || 0
      new_count = count + 1

      socket =
        socket
        |> put_signal(:count, new_count)
        |> PhoenixDatastar.Socket.patch_elements(
          "#count",
          {:safe, "<span id=\"count\">#{new_count}</span>"}
        )

      {:noreply, socket}
    end

    @impl PhoenixDatastar
    def render(assigns), do: ~H|<span id="count" data-text="$count"></span>|
  end

  defmodule StatelessViewWithAssigns do
    @moduledoc """
    A view that uses both assigns (server-side) and signals (client-side).
    Demonstrates that assigns are not sent as signals.
    """
    use PhoenixDatastar

    @impl PhoenixDatastar
    def mount(_params, _session, socket) do
      {:ok,
       socket
       |> Socket.assign(:user, %{name: "Alice", role: :admin})
       |> put_signal(:count, 0)}
    end

    @impl PhoenixDatastar
    def handle_event("greet", _params, socket) do
      # Assigns from mount should be available here
      name = socket.assigns.user.name

      {:noreply,
       socket
       |> put_signal(:greeting, "Hello #{name}!")
       |> PhoenixDatastar.Socket.patch_elements(
         "#greeting",
         {:safe, "<span id=\"greeting\">Hello #{name}!</span>"}
       )}
    end

    @impl PhoenixDatastar
    def render(assigns), do: ~H|<div>Welcome {@user.name}</div>|
  end

  setup do
    start_supervised!({Registry, keys: :unique, name: PhoenixDatastar.Registry})
    :ok
  end

  test "stateless view should not have stream path and not start server" do
    conn = Phoenix.ConnTest.build_conn()
    conn = Map.put(conn, :params, %{"_format" => "html"})

    conn =
      Plug.Conn.put_private(conn, :datastar, %{
        view: StatelessView,
        path: "/test",
        html_module: TestHTML
      })

    conn = PhoenixDatastar.PageController.mount(conn, %{})

    # If stateless, stream_path should be nil or empty.
    refute html_response(conn, 200) =~ "Stream: /test/stream"
  end

  test "stateless view should have event_path set" do
    conn = Phoenix.ConnTest.build_conn(:get, "/test")
    conn = Map.put(conn, :params, %{"_format" => "html"})

    conn =
      Plug.Conn.put_private(conn, :datastar, %{
        view: StatelessView,
        path: "/test",
        html_module: TestHTML
      })

    conn = PhoenixDatastar.PageController.mount(conn, %{})

    assert html_response(conn, 200) =~ "Event: /test/_event"
  end

  test "root path should have correct event_path without double slashes" do
    conn = Phoenix.ConnTest.build_conn()
    conn = Map.put(conn, :params, %{"_format" => "html"})

    conn =
      Plug.Conn.put_private(conn, :datastar, %{
        view: StatelessView,
        path: "/",
        html_module: TestHTML
      })

    conn = PhoenixDatastar.PageController.mount(conn, %{})

    response = html_response(conn, 200)

    # Should be "/_event" not "//_event"
    assert response =~ "Event: /_event"
    refute response =~ "Event: //_event"
  end

  test "stateless view handles events and returns SSE response with signals and patches" do
    conn =
      Phoenix.ConnTest.build_conn(:post, "/test/_event/increment", %{
        "event" => "increment",
        "session_id" => "test-session-123",
        "count" => 5
      })

    conn = Map.put(conn, :body_params, %{"count" => 5, "session_id" => "test-session-123"})
    conn = Plug.Conn.assign(conn, :base_path, "/test")

    conn = PhoenixDatastar.Plug.call(conn, view: StatelessViewWithSignals)

    assert conn.status == 200
    assert get_resp_header(conn, "content-type") == ["text/event-stream; charset=utf-8"]

    body = conn.resp_body
    assert body =~ "event: datastar-patch-elements"
    assert body =~ "selector #count"
    assert body =~ "<span id=\"count\">6</span>"
  end

  test "stateless view returns signal updates via put_signal" do
    conn =
      Phoenix.ConnTest.build_conn(:post, "/test/_event/increment", %{
        "event" => "increment",
        "session_id" => "test-session-123",
        "count" => 10
      })

    conn = Map.put(conn, :body_params, %{"count" => 10, "session_id" => "test-session-123"})
    conn = Plug.Conn.assign(conn, :base_path, "/test")

    conn = PhoenixDatastar.Plug.call(conn, view: StatelessViewWithSignals)

    body = conn.resp_body

    # Should include signal update for the new count
    assert body =~ "event: datastar-patch-signals"
    assert body =~ "count"
  end

  test "initial signals from mount are passed to template" do
    conn = Phoenix.ConnTest.build_conn()
    conn = Map.put(conn, :params, %{"_format" => "html"})

    conn =
      Plug.Conn.put_private(conn, :datastar, %{
        view: StatelessViewWithSignals,
        path: "/test",
        html_module: TestHTMLWithSignals
      })

    conn = PhoenixDatastar.PageController.mount(conn, %{})

    response = html_response(conn, 200)

    # The mount puts signal count: 0, so it should appear in initial_signals
    assert response =~ "count" and response =~ ":0"
  end

  test "assigns are not included in initial signals" do
    conn = Phoenix.ConnTest.build_conn()
    conn = Map.put(conn, :params, %{"_format" => "html"})

    conn =
      Plug.Conn.put_private(conn, :datastar, %{
        view: StatelessViewWithAssigns,
        path: "/test",
        html_module: TestHTMLWithSignals
      })

    conn = PhoenixDatastar.PageController.mount(conn, %{})

    response = html_response(conn, 200)

    # Signals should contain count but NOT user (which is an assign)
    assert response =~ "count"
    refute response =~ "Alice"
    refute response =~ "user"
  end

  test "internal assigns are not included in initial signals" do
    conn = Phoenix.ConnTest.build_conn()
    conn = Map.put(conn, :params, %{"_format" => "html"})

    conn =
      Plug.Conn.put_private(conn, :datastar, %{
        view: StatelessViewWithSignals,
        path: "/test",
        html_module: TestHTMLWithSignals
      })

    conn = PhoenixDatastar.PageController.mount(conn, %{})

    response = html_response(conn, 200)

    # Internal assigns should NOT appear in initial_signals
    refute response =~ "session_id"
    refute response =~ "base_path"
    refute response =~ "stream_path"
    refute response =~ "event_path"
  end

  test "default HTML module renders initial signals in data-signals" do
    conn = Phoenix.ConnTest.build_conn()
    conn = Map.put(conn, :params, %{"_format" => "html"})

    conn =
      Plug.Conn.put_private(conn, :datastar, %{
        view: StatelessViewWithSignals,
        path: "/test",
        html_module: nil
      })

    conn = PhoenixDatastar.PageController.mount(conn, %{})

    response = html_response(conn, 200)

    # DefaultHTML should render data-signals with session_id, event_path, and user signals
    assert response =~ "data-signals="
    assert response =~ "session_id"
    assert response =~ "event_path"
    assert response =~ "count"
  end

  test "stateless handle_event has access to assigns from mount" do
    conn =
      Phoenix.ConnTest.build_conn(:post, "/test/_event/greet", %{
        "event" => "greet",
        "session_id" => "test-session-123"
      })

    conn = Map.put(conn, :body_params, %{"session_id" => "test-session-123"})
    conn = Plug.Conn.assign(conn, :base_path, "/test")

    conn = PhoenixDatastar.Plug.call(conn, view: StatelessViewWithAssigns)

    assert conn.status == 200
    body = conn.resp_body

    # The handler reads socket.assigns.user.name from mount
    assert body =~ "Hello Alice!"
    assert body =~ "event: datastar-patch-elements"
    assert body =~ "event: datastar-patch-signals"
  end

  test "assigns with structs do not cause serialization errors" do
    conn = Phoenix.ConnTest.build_conn()
    conn = Map.put(conn, :params, %{"_format" => "html"})

    conn =
      Plug.Conn.put_private(conn, :datastar, %{
        view: StatelessViewWithAssigns,
        path: "/test",
        html_module: TestHTMLWithSignals
      })

    # This should not raise — the struct is in assigns, not signals
    conn = PhoenixDatastar.PageController.mount(conn, %{})
    assert conn.status == 200
  end
end
