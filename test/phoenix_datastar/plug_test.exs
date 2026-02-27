defmodule PhoenixDatastar.PlugTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Plug.Conn

  alias PhoenixDatastar.Plug, as: DatastarPlug
  alias PhoenixDatastar.Server
  alias PhoenixDatastar.Socket

  # Test view for live mode
  defmodule LiveTestView do
    use PhoenixDatastar, :live

    @impl PhoenixDatastar
    def mount(params, _session, socket) do
      socket =
        socket
        |> Socket.assign(:mounted, true)
        |> Socket.assign(:params, params)
        |> Socket.put_signal(:count, 0)

      {:ok, socket}
    end

    @impl PhoenixDatastar
    def render(assigns) do
      {:safe, "<div>Count: #{assigns[:count] || 0}</div>"}
    end

    @impl PhoenixDatastar
    def handle_event("increment", _payload, socket) do
      socket = Socket.update_signal(socket, :count, &(&1 + 1))
      {:noreply, socket}
    end

    def handle_event("patch_test", _payload, socket) do
      socket = Socket.patch_elements(socket, "#test", {:safe, "<span>Patched</span>"})
      {:noreply, socket}
    end

    def handle_event("stop", _payload, socket) do
      {:stop, socket}
    end
  end

  # Test view for stateless mode
  defmodule StatelessTestView do
    use PhoenixDatastar

    @impl PhoenixDatastar
    def mount(params, session, socket) do
      socket =
        socket
        |> Socket.assign(:mounted, true)
        |> Socket.assign(:params, params)
        |> Socket.assign(:session_data, session)
        |> Socket.put_signal(:initial, "value")

      {:ok, socket}
    end

    @impl PhoenixDatastar
    def render(assigns) do
      {:safe, "<div>Stateless: #{assigns[:mounted]}</div>"}
    end

    @impl PhoenixDatastar
    def handle_event("update", payload, socket) do
      socket = Socket.put_signal(socket, :message, payload["message"] || "default")
      {:noreply, socket}
    end

    def handle_event("patch_element", _payload, socket) do
      socket = Socket.patch_elements(socket, "#content", {:safe, "<p>Updated</p>"})
      {:noreply, socket}
    end

    def handle_event("execute_script", _payload, socket) do
      socket = Socket.execute_script(socket, "console.log('test')")
      {:noreply, socket}
    end

    def handle_event("stop", _payload, socket) do
      {:stop, socket}
    end

    def handle_event("error", _payload, _socket) do
      raise "Intentional error for testing"
    end

    def handle_event("test", _payload, socket) do
      socket = Socket.put_signal(socket, :tested, true)
      {:noreply, socket}
    end
  end

  # Test view with mount returning {:ok, socket, opts}
  defmodule MountWithOptsView do
    use PhoenixDatastar

    @impl PhoenixDatastar
    def mount(_params, _session, socket) do
      {:ok, Socket.assign(socket, :with_opts, true), temporary_assigns: []}
    end

    @impl PhoenixDatastar
    def render(_assigns), do: {:safe, "<div>With opts</div>"}

    @impl PhoenixDatastar
    def handle_event("test", _payload, socket) do
      {:noreply, Socket.put_signal(socket, :tested, true)}
    end
  end

  setup do
    # Start the Registry if not already started
    case Elixir.Registry.start_link(keys: :unique, name: PhoenixDatastar.Registry) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    # Generate unique session ID for each test
    session_id = "test-session-#{System.unique_integer([:positive])}"

    on_exit(fn ->
      # Try to stop the server if it's still running
      # Guard against Registry not being available
      try do
        case Elixir.Registry.lookup(PhoenixDatastar.Registry, session_id) do
          [{pid, _}] -> GenServer.stop(pid, :normal, 100)
          [] -> :ok
        end
      rescue
        ArgumentError -> :ok
      end
    end)

    %{session_id: session_id}
  end

  describe "init/1" do
    test "passes options through unchanged" do
      opts = [view: LiveTestView, some_option: :value]
      assert DatastarPlug.init(opts) == opts
    end

    test "handles empty options" do
      assert DatastarPlug.init([]) == []
    end
  end

  describe "call/2 - missing session_id" do
    test "returns 400 when session_id is missing from all sources" do
      conn =
        build_conn(:get, "/test/stream")
        |> Map.put(:params, %{})
        |> Map.put(:path_params, %{})
        |> Map.put(:query_params, %{})
        |> Map.put(:body_params, %{})

      conn = DatastarPlug.call(conn, view: LiveTestView)

      assert conn.status == 400
      assert conn.resp_body == "Missing session_id"
      assert conn.halted
    end

    test "returns 400 for POST without session_id" do
      conn =
        build_conn(:post, "/test/_event/click", %{"event" => "click"})
        |> Map.put(:path_params, %{})
        |> Map.put(:query_params, %{})

      conn = DatastarPlug.call(conn, view: StatelessTestView)

      assert conn.status == 400
      assert conn.resp_body == "Missing session_id"
    end
  end

  describe "call/2 - session_id sources" do
    test "reads session_id from path_params", %{session_id: session_id} do
      conn =
        build_conn(:post, "/test/_event/test", %{"event" => "update"})
        |> Map.put(:path_params, %{"session_id" => session_id})

      conn = DatastarPlug.call(conn, view: StatelessTestView)

      # Should proceed (not error on missing session_id)
      assert conn.status == 200
    end

    test "reads session_id from params", %{session_id: session_id} do
      conn =
        build_conn(:post, "/test/_event/test", %{"event" => "update", "session_id" => session_id})
        |> Map.put(:path_params, %{})

      conn = DatastarPlug.call(conn, view: StatelessTestView)

      assert conn.status == 200
    end

    test "reads session_id from _session_id param", %{session_id: session_id} do
      conn =
        build_conn(:post, "/test/_event/test", %{"event" => "update", "_session_id" => session_id})
        |> Map.put(:path_params, %{})

      conn = DatastarPlug.call(conn, view: StatelessTestView)

      assert conn.status == 200
    end

    test "reads session_id from datastar signals in GET query params", %{session_id: session_id} do
      signals_json = Jason.encode!(%{"session_id" => session_id})

      # For GET with SSE, we need to mock the SSE behavior
      # This test verifies the session_id is read; actual SSE tested separately
      conn =
        build_conn(:get, "/test/stream?datastar=#{URI.encode_www_form(signals_json)}")
        |> Map.put(:path_params, %{})

      # This will start SSE stream which we can't easily test without mocking
      # Instead, verify path parsing by testing with nil view (which returns 500)
      conn = DatastarPlug.call(conn, view: nil)

      # Should get 500 (SSE requires view) not 400 (missing session_id)
      assert conn.status == 500
      assert conn.resp_body == "SSE stream requires a view module"
    end
  end

  describe "call/2 - GET requests (SSE stream)" do
    test "returns 500 when view is nil", %{session_id: session_id} do
      conn =
        build_conn(:get, "/test/stream")
        |> Map.put(:path_params, %{})
        |> Map.put(:params, %{"session_id" => session_id})

      conn = DatastarPlug.call(conn, view: nil)

      assert conn.status == 500
      assert conn.resp_body == "SSE stream requires a view module"
      assert conn.halted
    end
  end

  describe "call/2 - POST requests (events)" do
    test "returns 400 when event parameter is missing", %{session_id: session_id} do
      conn =
        build_conn(:post, "/test/_event/test", %{"session_id" => session_id})
        |> Map.put(:path_params, %{})
        # No "event" in params

      conn = DatastarPlug.call(conn, view: StatelessTestView)

      assert conn.status == 400
      assert conn.resp_body == "Missing 'event' parameter"
    end

    test "handles stateless view events", %{session_id: session_id} do
      conn =
        build_conn(:post, "/test/_event/update", %{
          "event" => "update",
          "session_id" => session_id,
          "message" => "hello"
        })
        |> Map.put(:path_params, %{})

      conn = DatastarPlug.call(conn, view: StatelessTestView)

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["text/event-stream; charset=utf-8"]
      # Should contain signal patch for :message
      assert conn.resp_body =~ "datastar-patch-signals"
      assert conn.resp_body =~ "hello"
    end

    test "handles stateless view with patch_elements", %{session_id: session_id} do
      conn =
        build_conn(:post, "/test/_event/patch_element", %{
          "event" => "patch_element",
          "session_id" => session_id
        })
        |> Map.put(:path_params, %{})

      conn = DatastarPlug.call(conn, view: StatelessTestView)

      assert conn.status == 200
      assert conn.resp_body =~ "datastar-patch-elements"
      assert conn.resp_body =~ "#content"
      assert conn.resp_body =~ "Updated"
    end

    test "handles stateless view with execute_script", %{session_id: session_id} do
      conn =
        build_conn(:post, "/test/_event/execute_script", %{
          "event" => "execute_script",
          "session_id" => session_id
        })
        |> Map.put(:path_params, %{})

      conn = DatastarPlug.call(conn, view: StatelessTestView)

      assert conn.status == 200
      assert conn.resp_body =~ "datastar-patch-elements"
      assert conn.resp_body =~ "console.log"
    end

    test "handles stateless view returning {:stop, socket}", %{session_id: session_id} do
      conn =
        build_conn(:post, "/test/_event/stop", %{
          "event" => "stop",
          "session_id" => session_id
        })
        |> Map.put(:path_params, %{})

      conn = DatastarPlug.call(conn, view: StatelessTestView)

      assert conn.status == 200
      assert conn.resp_body == ""
    end

    test "handles stateless view mount returning {:ok, socket, opts}", %{session_id: session_id} do
      conn =
        build_conn(:post, "/test/_event/test", %{
          "event" => "test",
          "session_id" => session_id
        })
        |> Map.put(:path_params, %{})

      conn = DatastarPlug.call(conn, view: MountWithOptsView)

      assert conn.status == 200
      # Should contain signal patch for :tested
      assert conn.resp_body =~ "datastar-patch-signals"
      assert conn.resp_body =~ "tested"
    end

    test "handles errors in stateless handle_event gracefully", %{session_id: session_id} do
      conn =
        build_conn(:post, "/test/_event/error", %{
          "event" => "error",
          "session_id" => session_id
        })
        |> Map.put(:path_params, %{})

      conn = DatastarPlug.call(conn, view: StatelessTestView)

      assert conn.status == 500
      assert conn.resp_body == "Internal server error"
    end

    test "dispatches live view events to GenServer", %{session_id: session_id} do
      # Start the server first
      {:ok, _pid} = Server.ensure_started(LiveTestView, session_id, %{}, %{}, "/test")

      conn =
        build_conn(:post, "/test/_event/increment", %{
          "event" => "increment",
          "session_id" => session_id
        })
        |> Map.put(:path_params, %{})

      conn = DatastarPlug.call(conn, view: LiveTestView)

      # Live events return empty body (updates come via SSE)
      assert conn.status == 200
      assert conn.resp_body == ""

      # Verify the event was processed
      {:ok, _html, signals} = Server.get_snapshot(session_id)
      assert signals.count == 1
    end
  end

  describe "call/2 - unsupported methods" do
    test "returns 404 for unsupported HTTP methods", %{session_id: session_id} do
      conn =
        build_conn(:put, "/test/something", %{"session_id" => session_id})
        |> Map.put(:path_params, %{})

      conn = DatastarPlug.call(conn, view: StatelessTestView)

      assert conn.status == 404
      assert conn.resp_body == "Not Found"
    end

    test "returns 404 for DELETE method", %{session_id: session_id} do
      conn =
        build_conn(:delete, "/test/something", %{"session_id" => session_id})
        |> Map.put(:path_params, %{})

      conn = DatastarPlug.call(conn, view: StatelessTestView)

      assert conn.status == 404
    end

    test "returns 404 for PATCH method", %{session_id: session_id} do
      conn =
        build_conn(:patch, "/test/something", %{"session_id" => session_id})
        |> Map.put(:path_params, %{})

      conn = DatastarPlug.call(conn, view: StatelessTestView)

      assert conn.status == 404
    end
  end

  describe "base_path extraction" do
    test "extracts base_path by stripping /stream suffix", %{session_id: session_id} do
      # We can verify base_path extraction indirectly through the 500 error
      conn =
        build_conn(:get, "/my/app/counter/stream")
        |> Map.put(:path_params, %{})
        |> Map.put(:params, %{"session_id" => session_id})

      conn = DatastarPlug.call(conn, view: nil)

      # base_path should be "/my/app/counter"
      assert conn.assigns[:base_path] == "/my/app/counter"
    end

    test "extracts base_path by stripping /_event/:event suffix", %{session_id: session_id} do
      conn =
        build_conn(:post, "/my/app/counter/_event/click", %{
          "event" => "update",
          "session_id" => session_id
        })
        |> Map.put(:path_params, %{})

      conn = DatastarPlug.call(conn, view: StatelessTestView)

      assert conn.assigns[:base_path] == "/my/app/counter"
    end

    test "handles paths without stream or _event suffix", %{session_id: session_id} do
      conn =
        build_conn(:post, "/simple/path", %{
          "event" => "test",
          "session_id" => session_id
        })
        |> Map.put(:path_params, %{})

      conn = DatastarPlug.call(conn, view: StatelessTestView)

      # Path stays the same when no suffix to strip
      assert conn.assigns[:base_path] == "/simple/path"
    end

    test "handles root path with /stream", %{session_id: session_id} do
      conn =
        build_conn(:get, "/stream")
        |> Map.put(:path_params, %{})
        |> Map.put(:params, %{"session_id" => session_id})

      conn = DatastarPlug.call(conn, view: nil)

      assert conn.assigns[:base_path] == ""
    end
  end

  describe "stateless event - socket initialization" do
    test "initializes socket with correct assigns structure", %{session_id: session_id} do
      # Test socket initialization without fetch_session (not required for basic test)
      conn =
        build_conn(:post, "/my/base/path/_event/update", %{
          "event" => "update",
          "session_id" => session_id
        })
        |> Map.put(:path_params, %{})

      conn = DatastarPlug.call(conn, view: StatelessTestView)

      # The socket should have been created with proper assigns
      # We verify indirectly by checking the request succeeded
      assert conn.status == 200
    end

    test "clears events/signals from mount before handle_event", %{session_id: session_id} do
      # MountWithOptsView doesn't set signals in mount, so we test with StatelessTestView
      # which sets :initial signal in mount
      conn =
        build_conn(:post, "/test/_event/update", %{
          "event" => "update",
          "session_id" => session_id,
          "message" => "new"
        })
        |> Map.put(:path_params, %{})

      conn = DatastarPlug.call(conn, view: StatelessTestView)

      # Should only contain signal from handle_event, not from mount
      # The :initial signal from mount should have been cleared
      assert conn.resp_body =~ "message"
      # Initial from mount should be cleared before handle_event runs
      # So we only see what handle_event produced
    end
  end

  describe "SSE response format" do
    test "formats signals correctly in SSE response", %{session_id: session_id} do
      conn =
        build_conn(:post, "/test/_event/update", %{
          "event" => "update",
          "session_id" => session_id,
          "message" => "test_message"
        })
        |> Map.put(:path_params, %{})

      conn = DatastarPlug.call(conn, view: StatelessTestView)

      # Check SSE format
      assert conn.resp_body =~ "event: datastar-patch-signals\n"
      assert conn.resp_body =~ "data: signals "
      assert conn.resp_body =~ "test_message"
    end

    test "formats patch elements correctly in SSE response", %{session_id: session_id} do
      conn =
        build_conn(:post, "/test/_event/patch_element", %{
          "event" => "patch_element",
          "session_id" => session_id
        })
        |> Map.put(:path_params, %{})

      conn = DatastarPlug.call(conn, view: StatelessTestView)

      # Check SSE format for patches
      assert conn.resp_body =~ "event: datastar-patch-elements\n"
      assert conn.resp_body =~ "data: selector #content\n"
      assert conn.resp_body =~ "data: mode outer\n"
      assert conn.resp_body =~ "data: elements "
    end

    test "returns empty response when no signals or events", %{session_id: session_id} do
      # Create a view that returns {:noreply, socket} without modifying signals
      defmodule NoOpView do
        use PhoenixDatastar

        @impl PhoenixDatastar
        def mount(_params, _session, socket), do: {:ok, socket}

        @impl PhoenixDatastar
        def render(_assigns), do: {:safe, "<div></div>"}

        @impl PhoenixDatastar
        def handle_event("noop", _payload, socket), do: {:noreply, socket}
      end

      conn =
        build_conn(:post, "/test/_event/noop", %{
          "event" => "noop",
          "session_id" => session_id
        })
        |> Map.put(:path_params, %{})

      conn = DatastarPlug.call(conn, view: NoOpView)

      assert conn.status == 200
      # No signals or events, so response body should be empty
      assert conn.resp_body == ""
    end
  end
end
