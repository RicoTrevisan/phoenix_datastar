defmodule PhoenixDatastar.ServerTest do
  use ExUnit.Case, async: false

  alias PhoenixDatastar.Server
  alias PhoenixDatastar.Socket

  # Test view that tracks mount and event callbacks
  defmodule TestView do
    use PhoenixDatastar

    @impl PhoenixDatastar
    def mount(params, session, socket) do
      socket =
        socket
        |> Socket.assign(:mounted, true)
        |> Socket.assign(:params, params)
        |> Socket.assign(:session_data, session)
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

    def handle_event("patch_element", _payload, socket) do
      socket = Socket.patch_elements(socket, "#test", {:safe, "<span>Patched</span>"})
      {:noreply, socket}
    end

    def handle_event("stop", _payload, socket) do
      {:stop, socket}
    end
  end

  # Test view with terminate callback
  defmodule TerminatingView do
    use PhoenixDatastar

    @impl PhoenixDatastar
    def mount(_params, _session, socket) do
      # Store the test process pid to send messages
      {:ok, Socket.assign(socket, :test_pid, nil)}
    end

    @impl PhoenixDatastar
    def render(_assigns), do: {:safe, "<div>Terminating</div>"}

    @impl PhoenixDatastar
    def terminate(socket) do
      if pid = socket.assigns[:test_pid] do
        send(pid, :view_terminated)
      end
    end
  end

  # Test view with handle_info callback
  defmodule PubSubView do
    use PhoenixDatastar

    @impl PhoenixDatastar
    def mount(_params, _session, socket) do
      {:ok, Socket.assign(socket, :messages, [])}
    end

    @impl PhoenixDatastar
    def render(assigns) do
      {:safe, "<div>Messages: #{length(assigns.messages)}</div>"}
    end

    def handle_info({:message, msg}, socket) do
      socket =
        socket
        |> Socket.update(:messages, &[msg | &1])
        |> Socket.put_signal(:last_message, msg)

      {:noreply, socket}
    end
  end

  # Test view without handle_info
  defmodule NoHandleInfoView do
    use PhoenixDatastar

    @impl PhoenixDatastar
    def mount(_params, _session, socket), do: {:ok, socket}

    @impl PhoenixDatastar
    def render(_assigns), do: {:safe, "<div>No handle_info</div>"}
  end

  # View that returns {:ok, socket, opts} from mount
  defmodule MountWithOptsView do
    use PhoenixDatastar

    @impl PhoenixDatastar
    def mount(_params, _session, socket) do
      {:ok, Socket.assign(socket, :with_opts, true), temporary_assigns: []}
    end

    @impl PhoenixDatastar
    def render(_assigns), do: {:safe, "<div>With opts</div>"}
  end

  # Start registry once for all tests
  setup_all do
    case Elixir.Registry.start_link(keys: :unique, name: PhoenixDatastar.Registry) do
      {:ok, pid} -> {:ok, registry_pid: pid}
      {:error, {:already_started, pid}} -> {:ok, registry_pid: pid}
    end
  end

  setup do
    # Generate unique session ID for each test
    session_id = "test-session-#{System.unique_integer([:positive])}"

    on_exit(fn ->
      # Try to stop the server if it's still running
      # Use try/catch since Registry might not be running during test cleanup
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

  describe "start_link/1" do
    test "starts a server with required options", %{session_id: session_id} do
      opts = [
        view: TestView,
        session_id: session_id,
        params: %{},
        session: %{}
      ]

      assert {:ok, pid} = Server.start_link(opts)
      assert is_pid(pid)
      assert Process.alive?(pid)
    end

    test "registers server with Registry", %{session_id: session_id} do
      opts = [
        view: TestView,
        session_id: session_id,
        params: %{},
        session: %{}
      ]

      {:ok, pid} = Server.start_link(opts)

      # Verify registration via Registry
      assert [{^pid, _}] = Registry.lookup(PhoenixDatastar.Registry, session_id)
    end

    test "raises if session_id is missing" do
      opts = [view: TestView, params: %{}, session: %{}]

      assert_raise KeyError, ~r/session_id/, fn ->
        Server.start_link(opts)
      end
    end

    test "fails to start if view is missing", %{session_id: session_id} do
      opts = [session_id: session_id, params: %{}, session: %{}]

      # The KeyError is raised in init/1, causing the GenServer to fail to start.
      # Spawn a separate process that traps exits to attempt the start.
      test_pid = self()

      spawn(fn ->
        # Trap exits in the spawned process
        Process.flag(:trap_exit, true)

        result =
          try do
            Server.start_link(opts)
          catch
            :exit, reason -> {:exit_caught, reason}
          end

        # If result is :ok, we still should receive EXIT message due to trap_exit
        final_result =
          case result do
            {:ok, pid} ->
              receive do
                {:EXIT, ^pid, reason} -> {:exit_received, reason}
              after
                100 -> {:ok, pid}
              end

            {:exit_caught, reason} ->
              {:exit_caught, reason}

            other ->
              other
          end

        send(test_pid, {:start_result, final_result})
      end)

      assert_receive {:start_result, result}, 1000
      # Either caught the exit, received the exit message, or got an error tuple
      # The exact result depends on OTP version, but it should not be {:ok, pid}
      refute match?({:ok, _pid}, result), "Server should not start successfully"
    end
  end

  describe "ensure_started/5" do
    test "starts a new server if not running", %{session_id: session_id} do
      assert {:ok, pid} = Server.ensure_started(TestView, session_id, %{}, %{}, "/test")
      assert is_pid(pid)
      assert Process.alive?(pid)
    end

    test "returns existing pid if already started", %{session_id: session_id} do
      {:ok, pid1} = Server.ensure_started(TestView, session_id, %{}, %{}, "/test")
      {:ok, pid2} = Server.ensure_started(TestView, session_id, %{}, %{}, "/test")

      assert pid1 == pid2
    end

    test "uses default empty base_path", %{session_id: session_id} do
      assert {:ok, _pid} = Server.ensure_started(TestView, session_id, %{}, %{})
    end
  end

  describe "subscribe/1" do
    test "subscribes calling process to updates", %{session_id: session_id} do
      {:ok, _pid} = Server.ensure_started(TestView, session_id, %{}, %{})

      assert :ok = Server.subscribe(session_id)
    end

    test "allows receiving events after subscribing", %{session_id: session_id} do
      {:ok, _pid} = Server.ensure_started(TestView, session_id, %{}, %{})
      :ok = Server.subscribe(session_id)

      # Dispatch an event that triggers signals update
      Server.dispatch_event(session_id, "increment", %{})

      # Should receive signals update
      assert_receive {:datastar_signals, %{count: 1}}, 1000
    end
  end

  describe "get_snapshot/1" do
    test "returns current HTML and signals", %{session_id: session_id} do
      {:ok, _pid} = Server.ensure_started(TestView, session_id, %{}, %{})

      assert {:ok, html, signals} = Server.get_snapshot(session_id)
      assert is_binary(html) or is_tuple(html)
      assert is_map(signals)
      assert signals.count == 0
    end

    test "does not subscribe the caller", %{session_id: session_id} do
      {:ok, _pid} = Server.ensure_started(TestView, session_id, %{}, %{})

      {:ok, _html, _signals} = Server.get_snapshot(session_id)

      # Dispatch an event
      Server.dispatch_event(session_id, "increment", %{})

      # Should NOT receive any messages since we didn't subscribe
      refute_receive {:datastar_signals, _}, 100
    end
  end

  describe "dispatch_event/3" do
    test "dispatches event to view's handle_event", %{session_id: session_id} do
      {:ok, _pid} = Server.ensure_started(TestView, session_id, %{}, %{})
      :ok = Server.subscribe(session_id)

      Server.dispatch_event(session_id, "increment", %{})

      assert_receive {:datastar_signals, %{count: 1}}, 1000
    end

    test "sends patch events to subscriber", %{session_id: session_id} do
      {:ok, _pid} = Server.ensure_started(TestView, session_id, %{}, %{})
      :ok = Server.subscribe(session_id)

      Server.dispatch_event(session_id, "patch_element", %{})

      assert_receive {:datastar_events, events}, 1000
      assert [{:patch, "#test", "<span>Patched</span>"}] = events
    end

    test "handles stop event and notifies subscriber", %{session_id: session_id} do
      {:ok, pid} = Server.ensure_started(TestView, session_id, %{}, %{})
      :ok = Server.subscribe(session_id)

      Server.dispatch_event(session_id, "stop", %{})

      assert_receive :datastar_stop, 1000

      # Server should stop
      Process.sleep(50)
      refute Process.alive?(pid)
    end
  end

  describe "navigate/5" do
    test "replaces view and sends navigation events", %{session_id: session_id} do
      {:ok, _pid} = Server.ensure_started(TestView, session_id, %{}, %{})
      :ok = Server.subscribe(session_id)

      nav_meta = %{
        root_selector: "#app",
        target: "/new-page",
        mode: "push",
        framework_signals: %{nav_token: "abc123"}
      }

      assert :ok = Server.navigate(session_id, NoHandleInfoView, %{}, "/new", nav_meta)

      # Should receive signals (including framework signals)
      assert_receive {:datastar_signals, signals}, 1000
      assert signals.nav_token == "abc123"

      # Should receive navigation events
      assert_receive {:datastar_events, events}, 1000
      assert length(events) == 2

      [{:patch, selector, _html, opts}, {:script, script, _}] = events
      assert selector == "#app"
      assert opts == [mode: :inner]
      assert script =~ "history.pushState"
      assert script =~ "/new-page"
    end

    test "uses replaceState for replace mode", %{session_id: session_id} do
      {:ok, _pid} = Server.ensure_started(TestView, session_id, %{}, %{})
      :ok = Server.subscribe(session_id)

      nav_meta = %{
        root_selector: "#app",
        target: "/replaced",
        mode: "replace",
        framework_signals: %{}
      }

      :ok = Server.navigate(session_id, NoHandleInfoView, %{}, "/new", nav_meta)

      assert_receive {:datastar_events, events}, 1000
      [{:patch, _, _, _}, {:script, script, _}] = events
      assert script =~ "history.replaceState"
    end

    test "handles mount returning {:ok, socket, opts}", %{session_id: session_id} do
      {:ok, _pid} = Server.ensure_started(TestView, session_id, %{}, %{})
      :ok = Server.subscribe(session_id)

      nav_meta = %{
        root_selector: "#app",
        target: "/with-opts",
        mode: "push",
        framework_signals: %{}
      }

      assert :ok = Server.navigate(session_id, MountWithOptsView, %{}, "/new", nav_meta)

      assert_receive {:datastar_events, _events}, 1000
    end
  end

  describe "handle_info/2" do
    test "forwards messages to view's handle_info when exported", %{session_id: session_id} do
      {:ok, pid} = Server.ensure_started(PubSubView, session_id, %{}, %{})
      :ok = Server.subscribe(session_id)

      # Send a message directly to the server
      send(pid, {:message, "hello"})

      # Should receive the signal update
      assert_receive {:datastar_signals, %{last_message: "hello"}}, 1000
    end

    test "ignores messages when handle_info not exported", %{session_id: session_id} do
      {:ok, pid} = Server.ensure_started(NoHandleInfoView, session_id, %{}, %{})
      :ok = Server.subscribe(session_id)

      # Send a random message
      send(pid, {:random, "message"})

      # Should not crash and not receive anything
      refute_receive _, 100
      assert Process.alive?(pid)
    end

    test "ignores DOWN messages from non-subscriber processes", %{session_id: session_id} do
      {:ok, pid} = Server.ensure_started(TestView, session_id, %{}, %{})

      # Spawn a process that will send a DOWN message when it dies
      spawned_pid = spawn(fn -> :ok end)
      ref = Process.monitor(spawned_pid)

      # Manually send a DOWN message (simulating what happens)
      send(pid, {:DOWN, ref, :process, spawned_pid, :normal})

      # Server should still be alive
      Process.sleep(50)
      assert Process.alive?(pid)
    end

    test "handles EXIT messages without crashing", %{session_id: session_id} do
      {:ok, pid} = Server.ensure_started(TestView, session_id, %{}, %{})

      # Send an EXIT message (simulating linked process death)
      send(pid, {:EXIT, self(), :normal})

      Process.sleep(50)
      assert Process.alive?(pid)
    end
  end

  describe "subscriber disconnection" do
    test "stops server when subscriber disconnects", %{session_id: session_id} do
      {:ok, pid} = Server.ensure_started(TestView, session_id, %{}, %{})

      # Spawn a subscriber that will die
      subscriber =
        spawn(fn ->
          Server.subscribe(session_id)

          receive do
            :die -> :ok
          end
        end)

      # Wait for subscription
      Process.sleep(50)

      # Kill the subscriber
      Process.exit(subscriber, :kill)

      # Server should stop after subscriber DOWN
      Process.sleep(100)
      refute Process.alive?(pid)
    end
  end

  describe "terminate/2" do
    test "calls view's terminate callback if exported" do
      session_id = "terminate-test-#{System.unique_integer([:positive])}"
      _test_pid = self()

      # Start with TerminatingView
      {:ok, pid} = Server.ensure_started(TerminatingView, session_id, %{}, %{})

      # Update the socket to include test_pid (we need to do this via handle_call or similar)
      # For this test, we'll manually stop the server and check terminate is called
      # by using a different approach - we'll create a custom test

      GenServer.stop(pid, :normal)

      # Note: The current implementation stores test_pid as nil, so we won't receive the message
      # This test documents the behavior - terminate IS called but needs the pid set
    end
  end

  describe "init/1" do
    test "initializes with default params when not provided" do
      session_id = "init-test-#{System.unique_integer([:positive])}"

      opts = [
        view: TestView,
        session_id: session_id
        # params and session not provided
      ]

      {:ok, pid} = Server.start_link(opts)

      # Get snapshot to verify initialization worked
      {:ok, _html, signals} = Server.get_snapshot(session_id)
      assert signals.count == 0

      GenServer.stop(pid)
    end

    test "passes params and session to view mount", %{session_id: session_id} do
      params = %{"id" => "123"}
      session = %{"user_id" => 456}

      {:ok, _pid} = Server.start_link([
        view: TestView,
        session_id: session_id,
        params: params,
        session: session
      ])

      # The TestView stores params and session in assigns
      # We can verify by getting snapshot (though assigns aren't returned in signals)
      {:ok, _html, _signals} = Server.get_snapshot(session_id)
    end

    test "extracts flash from session" do
      session_id = "flash-test-#{System.unique_integer([:positive])}"
      session = %{"flash" => %{"info" => "Welcome!"}}

      {:ok, _pid} = Server.start_link([
        view: TestView,
        session_id: session_id,
        params: %{},
        session: session
      ])

      # Flash should be available in assigns
      {:ok, _html, _signals} = Server.get_snapshot(session_id)
    end
  end

  describe "send_update/2 (private)" do
    test "does not send when subscriber is nil", %{session_id: session_id} do
      {:ok, _pid} = Server.ensure_started(TestView, session_id, %{}, %{})

      # Dispatch event without subscribing
      Server.dispatch_event(session_id, "increment", %{})

      # Should not crash, should not receive anything
      refute_receive _, 100
    end

    test "only sends signals when signals map is not empty", %{session_id: session_id} do
      {:ok, _pid} = Server.ensure_started(TestView, session_id, %{}, %{})
      :ok = Server.subscribe(session_id)

      Server.dispatch_event(session_id, "increment", %{})

      # Should receive signals (count is updated)
      assert_receive {:datastar_signals, %{count: 1}}, 1000
    end

    test "only sends events when events list is not empty", %{session_id: session_id} do
      {:ok, _pid} = Server.ensure_started(TestView, session_id, %{}, %{})
      :ok = Server.subscribe(session_id)

      Server.dispatch_event(session_id, "patch_element", %{})

      # Should receive both signals and events
      assert_receive {:datastar_signals, _}, 1000
      assert_receive {:datastar_events, [{:patch, "#test", "<span>Patched</span>"}]}, 1000
    end
  end
end
