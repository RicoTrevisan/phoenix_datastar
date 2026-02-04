defmodule PhoenixDatastar.Server do
  @moduledoc """
  GenServer for live PhoenixDatastar views.

  Manages the socket state and handles:
  - Event dispatching from client
  - PubSub message forwarding to view's handle_info/2
  - SSE updates to subscribers
  - Cleanup on disconnect via terminate/1
  """

  use GenServer
  require Logger

  alias PhoenixDatastar.Socket
  alias PhoenixDatastar.Registry
  alias PhoenixDatastar.Helpers
  alias PhoenixDatastar.Elements
  alias PhoenixDatastar.Signals
  alias PhoenixDatastar.Scripts

  @doc """
  Starts a GenServer for a Datastar view session.

  ## Options

    * `:view` - Required. The view module.
    * `:session_id` - Required. Unique session identifier.
    * `:params` - Route params. Defaults to `%{}`.
    * `:session` - Plug session data. Defaults to `%{}`.
    * `:base_path` - Base path for event URLs. Defaults to `""`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    session_id = Keyword.fetch!(opts, :session_id)
    GenServer.start_link(__MODULE__, opts, name: Registry.via(session_id))
  end

  @doc """
  Ensures a GenServer is started for the given session.

  If already running, returns the existing pid. Idempotent.
  """
  @spec ensure_started(module(), String.t(), map(), map(), String.t()) ::
          {:ok, pid()} | {:error, term()}
  def ensure_started(view, session_id, params, session, base_path \\ "") do
    case start_link(
           view: view,
           session_id: session_id,
           params: params,
           session: session,
           base_path: base_path
         ) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      other -> other
    end
  end

  @doc """
  Subscribe the calling process to receive render updates.
  Does not return initial HTML (use get_snapshot/1 if needed).
  """
  @spec subscribe(String.t()) :: :ok
  def subscribe(session_id) do
    GenServer.call(Registry.via(session_id), {:subscribe, self()})
  end

  @doc """
  Get the current rendered HTML without subscribing.
  """
  @spec get_snapshot(String.t()) :: {:ok, String.t()}
  def get_snapshot(session_id) do
    GenServer.call(Registry.via(session_id), :get_snapshot)
  end

  @doc """
  Dispatches an event to the GenServer for handling.

  This is an async cast - the response is sent via the SSE stream.
  """
  @spec dispatch_event(String.t(), String.t(), map()) :: :ok
  def dispatch_event(session_id, event, payload) do
    GenServer.cast(Registry.via(session_id), {:event, event, payload})
  end

  @doc """
  Enters the SSE loop, receiving updates from the GenServer and sending them to the client.
  Takes a %PhoenixDatastar.SSE{} struct instead of a raw conn.

  Returns the SSE struct when the connection closes.
  """
  @spec enter_loop(PhoenixDatastar.SSE.t(), String.t()) :: PhoenixDatastar.SSE.t()
  def enter_loop(sse, session_id) do
    receive do
      {:datastar_update, html, _assigns} ->
        Logger.debug("SSE full update, size: #{byte_size(html)}")
        sse = Elements.patch(sse, html, selector: "#ds-live-#{session_id}", mode: :inner)
        enter_loop(sse, session_id)

      {:datastar_patches, patches} ->
        Logger.debug("SSE #{length(patches)} patch(es)")

        sse =
          Enum.reduce(patches, sse, fn {selector, html}, sse ->
            Elements.patch(sse, html, selector: selector)
          end)

        enter_loop(sse, session_id)

      {:datastar_signals, signals} ->
        Logger.debug("SSE signals: #{inspect(signals)}")
        sse = Signals.patch(sse, signals)
        enter_loop(sse, session_id)

      {:datastar_scripts, scripts} ->
        Logger.debug("SSE #{length(scripts)} script(s)")

        sse =
          Enum.reduce(scripts, sse, fn {script, opts}, sse ->
            Scripts.execute(sse, script, opts)
          end)

        enter_loop(sse, session_id)

      :datastar_stop ->
        Logger.info("SSE connection stopped for session: #{session_id}")
        sse
    after
      # Keep-alive: send a comment every 30 seconds to prevent timeout
      30_000 ->
        Logger.debug("SSE keepalive for session: #{session_id}")

        case Plug.Conn.chunk(sse.conn, ": keepalive\n\n") do
          {:ok, conn} ->
            enter_loop(%{sse | conn: conn}, session_id)

          {:error, _reason} ->
            Logger.info("SSE connection closed for session: #{session_id}")
            sse
        end
    end
  end

  @impl true
  def init(opts) do
    # Trap exits so we receive {:EXIT, ...} messages instead of being killed
    # This is important because the Plug process that starts us will die when SSE closes
    Process.flag(:trap_exit, true)

    view = Keyword.fetch!(opts, :view)
    session_id = Keyword.fetch!(opts, :session_id)
    params = Keyword.get(opts, :params, %{})
    session = Keyword.get(opts, :session, %{})
    base_path = Keyword.get(opts, :base_path, "")

    socket = %Socket{
      id: session_id,
      view: view,
      assigns: %{
        session_id: session_id,
        base_path: base_path,
        stream_path: Path.join(base_path, "stream"),
        event_path: Path.join(base_path, "_event")
      }
    }

    # Call the view's mount callback to initialize state
    {:ok, socket} = view.mount(params, session, socket)

    {:ok, %{view: view, socket: socket, subscriber: nil}}
  end

  @impl true
  def handle_call({:subscribe, pid}, _from, state) do
    # Monitor the subscriber so we can clean up if they disconnect
    Process.monitor(pid)
    {:reply, :ok, %{state | subscriber: pid}}
  end

  @impl true
  def handle_call(:get_snapshot, _from, %{view: view, socket: socket} = state) do
    html = render_html(view, socket)
    {:reply, {:ok, html}, state}
  end

  @impl true
  def handle_cast(
        {:event, evt, payload},
        %{view: view, socket: socket, subscriber: subscriber} = state
      ) do
    Logger.debug("Event: #{evt}")

    case view.handle_event(evt, payload, socket) do
      {:noreply, new_socket} ->
        send_update(subscriber, new_socket)
        # Clear patches and scripts after sending
        {:noreply, %{state | socket: %{new_socket | patches: [], scripts: []}}}

      {:stop, new_socket} ->
        if subscriber do
          send(subscriber, :datastar_stop)
        end

        {:stop, :normal, %{state | socket: new_socket}}
    end
  end

  @impl true
  def handle_info(
        {:DOWN, _ref, :process, pid, _reason},
        %{subscriber: pid, view: view, socket: socket} = state
      ) do
    # Subscriber disconnected via monitor - call terminate and stop
    call_view_terminate(view, socket)
    {:stop, :normal, %{state | subscriber: nil}}
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
    # Non-subscriber DOWN, ignore
    {:noreply, state}
  end

  # Handle EXIT from linked processes (the Plug process that started us)
  def handle_info({:EXIT, _pid, _reason}, %{view: view, socket: socket} = state) do
    # Linked process exited - call terminate and stop
    call_view_terminate(view, socket)
    {:stop, :normal, state}
  end

  def handle_info(msg, %{view: view, socket: socket, subscriber: subscriber} = state) do
    # Forward PubSub messages to the view's handle_info callback
    if function_exported?(view, :handle_info, 2) do
      case view.handle_info(msg, socket) do
        {:noreply, new_socket} ->
          if new_socket != socket and subscriber do
            send_update(subscriber, new_socket)
          end

          # Clear patches and scripts after sending
          {:noreply, %{state | socket: %{new_socket | patches: [], scripts: []}}}

        _ ->
          {:noreply, state}
      end
    else
      {:noreply, state}
    end
  end

  @impl true
  def terminate(_reason, %{view: view, socket: socket}) do
    # Call optional terminate callback on view for cleanup
    call_view_terminate(view, socket)
    :ok
  end

  defp send_update(nil, _socket), do: :ok

  defp send_update(subscriber, socket) do
    # Always send signals when assigns have changed
    signals = Helpers.user_signals(socket.assigns)

    if map_size(signals) > 0 do
      send(subscriber, {:datastar_signals, signals})
    end

    # Send patches if any exist
    if socket.patches != [] do
      send(subscriber, {:datastar_patches, socket.patches})
    end

    # Send scripts if any exist
    if socket.scripts != [] do
      send(subscriber, {:datastar_scripts, socket.scripts})
    end
  end

  defp call_view_terminate(view, socket) do
    if function_exported?(view, :terminate, 1) do
      view.terminate(socket)
    end
  end

  defp render_html(view, socket), do: Helpers.render_html(view, socket)
end
