defmodule PhoenixDatastar.Plug do
  @moduledoc """
  Plug for handling PhoenixDatastar requests.

  Handles SSE streams and event dispatch:
  - GET /path/stream - Maintains SSE connection for server-pushed updates (live views)
  - POST /path/_event/:event - Handles events for all views
  """

  @behaviour Plug
  import Plug.Conn
  require Logger

  alias PhoenixDatastar.Server
  alias PhoenixDatastar.Helpers
  alias PhoenixDatastar.SSE

  @doc """
  Initializes the plug with options.

  ## Options

    * `:view` - The view module to handle requests. Required for SSE streams,
      optional for the global event endpoint.
  """
  @impl Plug
  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @doc """
  Handles incoming requests for Datastar views.

  Dispatches based on HTTP method:
  - GET: SSE stream connection
  - POST: Event dispatch to GenServer
  """
  @impl Plug
  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, opts) do
    conn = fetch_query_params(conn)
    view = Keyword.get(opts, :view)

    # Get base path for event URLs (strip /stream or /event/... suffix)
    base_path = get_base_path(conn.request_path)
    conn = assign(conn, :base_path, base_path)

    # session_id is required for all requests
    # For GET requests, read from Datastar signals; for POST, from params
    signals = PhoenixDatastar.Signals.read(conn)

    session_id =
      conn.path_params["session_id"] ||
        signals["session_id"] ||
        conn.params["session_id"] ||
        conn.params["_session_id"]

    if is_nil(session_id) do
      Logger.error("Missing session_id in PhoenixDatastar.Plug request")

      conn
      |> send_resp(400, "Missing session_id")
      |> halt()
    else
      dispatch(conn, conn.method, view, session_id)
    end
  end

  defp get_base_path(path) do
    path
    |> String.replace(~r"/stream$", "")
    |> String.replace(~r"/_event/[^/]+$", "")
  end

  # GET /stream - SSE connection (requires view)
  defp dispatch(conn, "GET", nil, _session_id) do
    conn
    |> send_resp(500, "SSE stream requires a view module")
    |> halt()
  end

  defp dispatch(conn, "GET", view, session_id) do
    Logger.debug("SSE connection: #{session_id}")

    # GenServer should already exist from page load, but ensure_started is idempotent
    session = Helpers.get_session_map(conn)
    base_path = conn.assigns[:base_path] || get_base_path(conn.request_path)
    {:ok, _pid} = Server.ensure_started(view, session_id, conn.params, session, base_path)

    # Subscribe to receive updates (initial HTML already rendered on page load)
    :ok = Server.subscribe(session_id)

    # Prepare conn for SSE and create SSE struct
    sse =
      conn
      |> put_resp_content_type("text/event-stream")
      |> put_resp_header("cache-control", "no-cache")
      |> put_resp_header("connection", "keep-alive")
      |> send_chunked(200)
      |> SSE.new()

    # Enter loop directly - no initial patch needed, content already on page
    # Returns sse struct when connection closes - extract conn to satisfy Plug contract
    sse = Server.enter_loop(sse, session_id)
    sse.conn
  end

  # POST /_event/:event - per-page event route (all views)
  defp dispatch(conn, "POST", view, session_id) do
    event = conn.params["event"]

    if is_nil(event) do
      send_resp(conn, 400, "Missing 'event' parameter")
    else
      if PhoenixDatastar.live?(view) do
        Logger.debug("Live event: #{event}")
        # Dispatch event to the GenServer - updates come via SSE stream
        Server.dispatch_event(session_id, event, conn.params)
        send_resp(conn, 200, "")
      else
        Logger.debug("Stateless event: #{event}")
        handle_stateless_event(conn, view, session_id, event)
      end
    end
  end

  defp dispatch(conn, _method, _view, _session_id) do
    send_resp(conn, 404, "Not Found")
  end

  # Handle stateless view events synchronously
  defp handle_stateless_event(conn, view, session_id, event) do
    signals = PhoenixDatastar.Signals.read(conn)
    base_path = conn.assigns[:base_path] || get_base_path(conn.request_path)

    # Convert string keys to atoms for assigns compatibility
    signal_assigns =
      signals
      |> Enum.reject(fn {k, _} -> k == "session_id" end)
      |> Enum.map(fn {k, v} -> {String.to_atom(k), v} end)
      |> Map.new()

    # Create socket from signals (no mount call - state comes from client)
    socket = %PhoenixDatastar.Socket{
      id: session_id,
      view: view,
      assigns:
        Map.merge(
          %{
            session_id: session_id,
            base_path: base_path,
            stream_path: nil,
            event_path: Path.join(base_path, "_event")
          },
          signal_assigns
        ),
      patches: [],
      scripts: []
    }

    try do
      case view.handle_event(event, conn.params, socket) do
        {:noreply, new_socket} ->
          response_body = build_sse_response(new_socket)

          conn
          |> put_resp_content_type("text/event-stream")
          |> send_resp(200, response_body)

        {:stop, _socket} ->
          send_resp(conn, 200, "")
      end
    rescue
      e ->
        Logger.error(
          "Stateless event error: #{inspect(e)}\n#{Exception.format_stacktrace(__STACKTRACE__)}"
        )

        send_resp(conn, 500, "Internal server error")
    end
  end

  # Build SSE response body from socket patches, signals, and scripts
  defp build_sse_response(socket) do
    events = []

    # Add signal patches (only user signals, excluding system assigns)
    user_signals = Helpers.user_signals(socket.assigns)

    events =
      if map_size(user_signals) > 0 do
        events ++
          [SSE.format_event("datastar-patch-signals", ["signals #{Jason.encode!(user_signals)}"])]
      else
        events
      end

    # Add element patches
    events =
      Enum.reduce(socket.patches, events, fn {selector, html}, acc ->
        acc ++
          [
            SSE.format_event("datastar-patch-elements", [
              "selector #{selector}",
              "mode outer",
              "elements #{html}"
            ])
          ]
      end)

    # Add scripts
    events =
      Enum.reduce(socket.scripts, events, fn {script, _opts}, acc ->
        script_html = "<script>#{script}</script>"

        acc ++
          [
            SSE.format_event("datastar-patch-elements", [
              "selector body",
              "mode append",
              "elements #{script_html}"
            ])
          ]
      end)

    Enum.join(events, "")
  end
end
