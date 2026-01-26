defmodule PhoenixDatastar.Plug do
  @moduledoc """
  Plug for handling PhoenixDatastar requests.

  Handles SSE streams and event dispatch:
  - GET /stream - Maintains SSE connection for server-pushed updates
  - POST /event/:event - Dispatches events to GenServer
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

    * `:view` - Required. The view module to handle requests.
  """
  @impl Plug
  @spec init(keyword()) :: keyword()
  def init(opts) do
    unless Keyword.has_key?(opts, :view) do
      raise ArgumentError, "PhoenixDatastar.Plug requires a :view option"
    end

    opts
  end

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
    view = Keyword.fetch!(opts, :view)

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
    |> String.replace(~r"/event/[^/]+$", "")
  end

  # GET /stream - SSE connection
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

  # POST /event/:event - dispatch to GenServer
  defp dispatch(conn, "POST", _view, session_id) do
    event = conn.params["event"]

    if event do
      Logger.debug("Event: #{event}")

      # Dispatch event to the GenServer
      Server.dispatch_event(session_id, event, conn.params)

      # Return empty 200 OK - updates come via the SSE stream
      send_resp(conn, 200, "")
    else
      send_resp(conn, 400, "Missing 'event' parameter")
    end
  end

  defp dispatch(conn, _method, _view, _session_id) do
    send_resp(conn, 404, "Not Found")
  end
end
