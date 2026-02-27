defmodule PhoenixDatastar.NavPlug do
  @moduledoc """
  Global in-session navigation endpoint.

  Handles soft navigation between live views within the same `datastar_session`.
  When a user navigates (via `navigate/2` or `<.ds_link>`), this plug:

  1. Verifies the signed `nav_token` (using Phoenix.Token-based signing).
  2. Matches the target path against registered routes via `PhoenixDatastar.RouteRegistry`.
  3. Checks the target is a live view in the same `datastar_session` as the source.
  4. If valid: calls `Server.navigate/5` to swap the view in the existing GenServer,
     pushing new HTML, signals, and a `pushState` script through the SSE stream.
     A fresh `nav_token` is issued for subsequent navigations.
  5. If invalid: falls back to a full page reload via `window.location`.

  ## Expected route

      post "/__datastar/nav", PhoenixDatastar.NavPlug, :navigate
  """

  @behaviour Plug
  import Plug.Conn

  alias PhoenixDatastar.{RouteRegistry, SSE, Server, StreamToken}

  @doc false
  @impl Plug
  def init(opts), do: opts

  @doc false
  @impl Plug
  def call(conn, _opts) do
    conn = fetch_query_params(conn)
    target = conn.params["_ds_to"]
    target_path = target && (URI.parse(target).path || "/")
    token = conn.params["nav_token"] || conn.params["token"]

    with true <- is_binary(target),
         true <- is_binary(token),
         {:ok, payload} <- StreamToken.verify(conn, token),
         router when not is_nil(router) <- conn.private[:phoenix_router],
         %{datastar: target_meta, path_params: path_params} <-
           RouteRegistry.match(router, "GET", target_path, conn.host),
         true <- payload["session_name"] == target_meta.session_name,
         true <- PhoenixDatastar.live?(target_meta.view) do
      soft_navigate(conn, payload, target_meta, path_params, target_path)
    else
      _ ->
        fallback_reload(conn, target || "/")
    end
  end

  defp soft_navigate(conn, payload, target_meta, path_params, target) do
    session_id = payload["session_id"]
    root_selector = target_meta.root_selector || "#app"
    mode = conn.params["_ds_mode"] || "push"

    next_token =
      StreamToken.sign(conn, %{
        "session_id" => session_id,
        "session_name" => target_meta.session_name
      })

    nav_meta = %{
      root_selector: root_selector,
      target: target,
      mode: mode,
      framework_signals: %{
        session_id: session_id,
        event_path: Path.join(target, "_event"),
        nav_path: "/__datastar/nav",
        nav_token: next_token
      }
    }

    :ok = Server.navigate(session_id, target_meta.view, path_params, target, nav_meta)

    # Return empty SSE — the actual data flows through the existing stream
    conn
    |> put_resp_content_type("text/event-stream")
    |> send_resp(200, ": nav-ack\n\n")
  end

  defp fallback_reload(conn, target) do
    body =
      SSE.format_event("datastar-patch-elements", [
        "selector body",
        "mode append",
        "elements <script>window.location='#{target}'</script>"
      ])

    conn
    |> put_resp_content_type("text/event-stream")
    |> send_resp(200, body)
  end
end
