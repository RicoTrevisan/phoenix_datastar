defmodule PhoenixDatastar.StreamPlug do
  @moduledoc """
  Global stream endpoint for Datastar live sessions.

  Handles `POST /__datastar/stream?token=...` requests. Verifies the stream token
  (using Phoenix.Token-based signing), subscribes to the session's GenServer, and
  enters the SSE loop (`PhoenixDatastar.Server.enter_loop/2`).

  Returns 401 if the token is missing or invalid. Returns 409 if the GenServer
  is no longer running (e.g., session expired), signaling the client to reload.

  ## Expected route

      post "/__datastar/stream", PhoenixDatastar.StreamPlug, :stream
  """

  import Plug.Conn

  alias PhoenixDatastar.{SSE, Server, StreamToken}

  @behaviour Plug

  @doc false
  @impl Plug
  def init(opts), do: opts

  @doc false
  @impl Plug
  def call(conn, _opts) do
    conn = fetch_query_params(conn)

    with token when is_binary(token) <- conn.params["token"],
         {:ok, payload} <- StreamToken.verify(conn, token) do
      open_stream(conn, payload)
    else
      _ ->
        conn
        |> send_resp(401, "Invalid stream token")
        |> halt()
    end
  end

  defp open_stream(conn, payload) do
    session_id = payload["session_id"]

    case safe_subscribe(session_id) do
      :ok ->
        sse =
          conn
          |> put_resp_content_type("text/event-stream")
          |> put_resp_header("cache-control", "no-cache")
          |> put_resp_header("connection", "keep-alive")
          |> send_chunked(200)
          |> SSE.new()

        sse = Server.enter_loop(sse, session_id)
        sse.conn

      :error ->
        conn
        |> put_resp_header("x-datastar-location", conn.request_path)
        |> send_resp(409, "stream_requires_reload")
        |> halt()
    end
  end

  defp safe_subscribe(session_id) do
    Server.subscribe(session_id)
    :ok
  catch
    :exit, _ -> :error
  end
end
