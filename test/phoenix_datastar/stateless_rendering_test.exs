defmodule PhoenixDatastar.StatelessRenderingTest do
  use ExUnit.Case
  import Phoenix.ConnTest
  import Plug.Conn

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
        path: "/test"
      })

    conn = PhoenixDatastar.PageController.mount(conn, %{})

    # stream_path should be nil for stateless views
    assert conn.assigns[:datastar_stream_path] == nil
    # session_id should be generated
    assert is_binary(conn.assigns[:datastar_session_id])
  end

  test "stateless view should have event_path set" do
    conn = Phoenix.ConnTest.build_conn()
    conn = Map.put(conn, :params, %{"_format" => "html"})

    conn =
      Plug.Conn.put_private(conn, :datastar, %{
        view: StatelessView,
        path: "/test"
      })

    conn = PhoenixDatastar.PageController.mount(conn, %{})

    assert conn.assigns[:datastar_event_path] == "/test/_event"
  end

  test "root path should have correct event_path without double slashes" do
    conn = Phoenix.ConnTest.build_conn()
    conn = Map.put(conn, :params, %{"_format" => "html"})

    conn =
      Plug.Conn.put_private(conn, :datastar, %{
        view: StatelessView,
        path: "/"
      })

    conn = PhoenixDatastar.PageController.mount(conn, %{})

    # Should be "/_event" not "//_event"
    assert conn.assigns[:datastar_event_path] == "/_event"
  end

  test "stateless view renders content through PageHTML" do
    conn = Phoenix.ConnTest.build_conn()
    conn = Map.put(conn, :params, %{"_format" => "html"})

    conn =
      Plug.Conn.put_private(conn, :datastar, %{
        view: StatelessView,
        path: "/test"
      })

    conn = PhoenixDatastar.PageController.mount(conn, %{})

    # The response should contain the view's rendered content
    assert html_response(conn, 200) =~ "Hello"
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
end
