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

  defmodule StatelessViewWithEvent do
    use PhoenixDatastar

    @impl PhoenixDatastar
    def mount(_params, _session, socket) do
      {:ok, PhoenixDatastar.Socket.assign(socket, :count, 0)}
    end

    @impl PhoenixDatastar
    def handle_event("increment", _params, socket) do
      new_count = socket.assigns.count + 1
      socket = PhoenixDatastar.Socket.assign(socket, :count, new_count)

      socket =
        PhoenixDatastar.Socket.patch_elements(
          socket,
          "#count",
          &render_count/1
        )

      {:noreply, socket}
    end

    defp render_count(assigns) do
      ~H|<span id="count"><%= @count %></span>|
    end

    @impl PhoenixDatastar
    def render(assigns), do: ~H|<span id="count"><%= @count %></span>|
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

    # Check rendered HTML
    # If stateless, stream_path should be nil or empty.
    refute html_response(conn, 200) =~ "Stream: /test/stream"
  end

  test "stateless view should have event_path set" do
    conn = Phoenix.ConnTest.build_conn()
    conn = Map.put(conn, :params, %{"_format" => "html"})

    conn =
      Plug.Conn.put_private(conn, :datastar, %{
        view: StatelessView,
        path: "/test",
        html_module: TestHTML
      })

    conn = PhoenixDatastar.PageController.mount(conn, %{})

    # Check that event_path is set for stateless views
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

  test "stateless view handles events and returns SSE response" do
    # Simulate a POST to /test/_event/increment
    conn =
      Phoenix.ConnTest.build_conn(:post, "/test/_event/increment", %{
        "event" => "increment",
        "session_id" => "test-session-123"
      })

    # Add signals via body (simulating Datastar sending signals)
    conn = Map.put(conn, :body_params, %{"count" => 5, "session_id" => "test-session-123"})
    conn = Plug.Conn.assign(conn, :base_path, "/test")

    # Call the plug directly with the view
    conn = PhoenixDatastar.Plug.call(conn, view: StatelessViewWithEvent)

    # Check response
    assert conn.status == 200
    assert get_resp_header(conn, "content-type") == ["text/event-stream; charset=utf-8"]

    # Check that response contains SSE-formatted patches
    body = conn.resp_body
    assert body =~ "event: datastar-patch-elements"
    assert body =~ "selector #count"
    assert body =~ "<span id=\"count\">6</span>"
  end

  test "stateless view returns signal updates" do
    conn =
      Phoenix.ConnTest.build_conn(:post, "/test/_event/increment", %{
        "event" => "increment",
        "session_id" => "test-session-123"
      })

    conn = Map.put(conn, :body_params, %{"count" => 10, "session_id" => "test-session-123"})
    conn = Plug.Conn.assign(conn, :base_path, "/test")

    conn = PhoenixDatastar.Plug.call(conn, view: StatelessViewWithEvent)

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
        view: StatelessViewWithEvent,
        path: "/test",
        html_module: TestHTMLWithSignals
      })

    conn = PhoenixDatastar.PageController.mount(conn, %{})

    response = html_response(conn, 200)

    # The mount assigns count: 0, so it should appear in initial_signals
    # HTML entities are encoded in the response, so quotes become &quot;
    assert response =~ "count" and response =~ ":0"
  end

  test "initial signals exclude internal assigns" do
    conn = Phoenix.ConnTest.build_conn()
    conn = Map.put(conn, :params, %{"_format" => "html"})

    conn =
      Plug.Conn.put_private(conn, :datastar, %{
        view: StatelessViewWithEvent,
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
        view: StatelessViewWithEvent,
        path: "/test",
        html_module: nil
      })

    conn = PhoenixDatastar.PageController.mount(conn, %{})

    response = html_response(conn, 200)

    # DefaultHTML should render data-signals with both session_id and user assigns
    assert response =~ "data-signals="
    assert response =~ "session_id"
    assert response =~ "count"
  end
end
