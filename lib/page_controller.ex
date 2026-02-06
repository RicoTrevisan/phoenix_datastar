defmodule PhoenixDatastar.PageController do
  @moduledoc """
  Controller for rendering the initial PhoenixDatastar page.

  Generates session ID, starts GenServer, and renders the initial HTML.
  Sets `datastar_session_id`, `datastar_stream_path`, and `datastar_event_path`
  on `conn.assigns` so the root layout can consume them.
  """

  @session_id_bytes 16

  use Phoenix.Controller, formats: [:html]

  alias PhoenixDatastar.Server
  alias PhoenixDatastar.Helpers

  @doc """
  Mounts a Datastar view.

  Expects `conn.private.datastar` to contain:
    * `:view` - The view module
    * `:path` - The base path
  """
  @spec mount(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def mount(conn, _params) do
    %{view: view, path: path} = conn.private.datastar

    session_id = generate_session_id()
    session = Helpers.get_session_map(conn)

    # Event path is the same format for all views
    # Use Path.join to handle root path "/" correctly (avoids "//")
    event_path = Path.join(path, "_event")

    {inner_html, stream_path} =
      if PhoenixDatastar.live?(view) do
        stream_path = Path.join(path, "stream")
        # Start GenServer for this session
        {:ok, _pid} = Server.ensure_started(view, session_id, conn.params, session, path)

        # Get rendered HTML from GenServer
        {:ok, inner_html} = Server.get_snapshot(session_id)

        {inner_html, stream_path}
      else
        # Stateless: Render directly without GenServer
        socket = %PhoenixDatastar.Socket{
          id: session_id,
          view: view,
          assigns: %{
            session_id: session_id,
            base_path: path,
            stream_path: nil,
            event_path: event_path
          }
        }

        socket =
          case view.mount(conn.params, session, socket) do
            {:ok, socket} -> socket
            {:ok, socket, _opts} -> socket
          end

        inner_html = Helpers.render_html(view, socket)
        {inner_html, nil}
      end

    conn
    |> assign(:datastar_session_id, session_id)
    |> assign(:datastar_stream_path, stream_path)
    |> assign(:datastar_event_path, event_path)
    |> put_view(PhoenixDatastar.PageHTML)
    |> render(:mount,
      inner_html: inner_html,
      page_title: "#{Helpers.get_view_name(view)} - Datastar"
    )
  end

  defp generate_session_id do
    @session_id_bytes
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end
end
