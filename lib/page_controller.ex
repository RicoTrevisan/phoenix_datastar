defmodule PhoenixDatastar.PageController do
  @moduledoc """
  Controller for rendering the initial PhoenixDatastar page.

  Generates session ID, starts GenServer, and renders the initial HTML.

  ## Configuration

  The HTML module used for rendering can be configured:

  1. Per-route via the `datastar/3` macro:

      datastar "/counter", CounterStar, html_module: MyAppWeb.DatastarHTML

  2. Globally via application config:

      config :phoenix_datastar, :html_module, MyAppWeb.DatastarHTML
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
    * `:html_module` - Optional HTML module override
  """
  @spec mount(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def mount(conn, _params) do
    %{view: view, path: path} = conn.private.datastar
    html_module = get_html_module(conn)

    session_id = generate_session_id()
    session = Helpers.get_session_map(conn)

    {inner_html, stream_path} =
      if PhoenixDatastar.live?(view) do
        stream_path = "#{path}/stream"
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
            stream_path: nil
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
    |> put_view(html_module)
    |> render(:mount,
      session_id: session_id,
      stream_path: stream_path,
      base_path: path,
      inner_html: inner_html,
      page_title: "#{Helpers.get_view_name(view)} - Datastar"
    )
  end

  defp get_html_module(conn) do
    conn.private.datastar[:html_module] ||
      Application.get_env(:phoenix_datastar, :html_module) ||
      raise """
      No HTML module configured for PhoenixDatastar.

      Configure it globally:

          config :phoenix_datastar, :html_module, MyAppWeb.DatastarHTML

      Or per-route:

          datastar "/path", MyView, html_module: MyAppWeb.DatastarHTML
      """
  end

  defp generate_session_id do
    @session_id_bytes
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end
end
