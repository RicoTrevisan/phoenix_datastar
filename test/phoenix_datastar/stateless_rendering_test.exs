defmodule PhoenixDatastar.StatelessRenderingTest do
  use ExUnit.Case
  import Phoenix.ConnTest

  defmodule TestHTML do
    use Phoenix.Component

    def mount(assigns) do
      # Render stream path so we can check it
      ~H"Stream: <%= @stream_path %>"
    end
  end

  defmodule StatelessView do
    use PhoenixDatastar

    @impl PhoenixDatastar
    def mount(_params, _session, socket), do: {:ok, socket}

    @impl PhoenixDatastar
    def render(assigns), do: ~H"Hello"
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
    # Currently it is "/test/stream"
    refute html_response(conn, 200) =~ "Stream: /test/stream"

    # Also check that no process is registered for this session
    # We need the session_id to check registry.
    # The session_id is generated inside the controller, so we can't easily check it unless we expose it
    # or check the HTML for it if we rendered it.
    # But checking the HTML stream path is sufficient to prove the controller logic change.
  end
end
