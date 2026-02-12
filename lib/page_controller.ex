defmodule PhoenixDatastar.PageController do
  @moduledoc """
  Controller for rendering the initial PhoenixDatastar page.

  Generates session ID, starts GenServer, and renders the initial HTML.

  By default, `PhoenixDatastar.DefaultHTML` is used as the mount template.
  To customize the wrapper, you can override it:

  1. Globally via application config:

      config :phoenix_datastar, :html_module, MyAppWeb.DatastarHTML

  2. Per-route via the `datastar/3` macro:

      datastar "/counter", CounterStar, html_module: MyAppWeb.DatastarHTML

  See `PhoenixDatastar.DefaultHTML` for a custom module example.
  """

  @session_id_bytes 16

  use Phoenix.Controller, formats: [:html]

  alias PhoenixDatastar.Helpers
  alias PhoenixDatastar.Server
  alias PhoenixDatastar.Socket

  @doc """
  Mounts a Datastar view.

  Expects `conn.private.datastar` to contain:
    * `:view` - The view module
    * `:path` - The base path
    * `:html_module` - Optional HTML module override (defaults to `PhoenixDatastar.DefaultHTML`)
  """
  @spec mount(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def mount(conn, _params) do
    %{view: view} = conn.private.datastar
    html_module = get_html_module(conn)

    # Use the actual request path (with resolved dynamic segments) instead of
    # the compile-time route pattern (which may contain :param placeholders).
    # e.g., "/acme-corporation" instead of "/:workspace_slug"
    resolved_path = conn.request_path

    session_id = generate_session_id()
    session = Helpers.get_session_map(conn)
    live? = PhoenixDatastar.live?(view)

    {inner_html, initial_signals} =
      if live? do
        # Start GenServer for this session
        {:ok, _pid} = Server.ensure_started(view, session_id, conn.params, session, resolved_path)

        # Get rendered HTML and initial signals from GenServer
        {:ok, inner_html, initial_signals} = Server.get_snapshot(session_id)

        {inner_html, initial_signals}
      else
        # Stateless: Render directly without GenServer
        socket =
          Socket.new(session_id, view, resolved_path,
            live: false,
            flash: Map.get(session, "flash", %{})
          )

        socket =
          case view.mount(conn.params, session, socket) do
            {:ok, socket} -> socket
            {:ok, socket, _opts} -> socket
          end

        inner_html = Helpers.render_html(view, socket)
        {inner_html, socket.signals}
      end

    stream_path = if live?, do: Path.join(resolved_path, "stream")
    event_path = Path.join(resolved_path, "_event")

    conn
    |> put_view(html_module)
    |> render(:mount,
      session_id: session_id,
      stream_path: stream_path,
      event_path: event_path,
      base_path: resolved_path,
      inner_html: inner_html,
      initial_signals: initial_signals,
      page_title: "#{Helpers.get_view_name(view)}"
    )
  end

  defp get_html_module(conn) do
    conn.private.datastar[:html_module] ||
      Application.get_env(:phoenix_datastar, :html_module) ||
      PhoenixDatastar.DefaultHTML
  end

  defp generate_session_id do
    @session_id_bytes
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end
end
