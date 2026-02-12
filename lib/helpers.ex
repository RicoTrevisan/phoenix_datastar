defmodule PhoenixDatastar.Helpers do
  @moduledoc """
  Shared helper functions for PhoenixDatastar modules.
  """

  @doc """
  Extracts the session map from a Plug.Conn.

  Merges the Plug session (from the session store) with all `conn.assigns`
  set by plugs in the pipeline. Assign keys are stringified so they can be
  pattern-matched in `mount/3` the same way as regular session keys.

  Returns the session data if available, otherwise an empty map.
  """
  @spec get_session_map(Plug.Conn.t()) :: map()
  def get_session_map(conn) do
    session =
      if conn.private[:plug_session] do
        Plug.Conn.get_session(conn)
      else
        %{}
      end

    # Forward all conn.assigns into the session with string keys.
    # This ensures any data set by plugs (current_user, current_scope, etc.)
    # is available in the view's mount/3 callback.
    conn_assigns =
      conn.assigns
      |> Map.drop([:layout])
      |> Map.new(fn {k, v} -> {to_string(k), v} end)

    # Ensure flash always has a default value
    conn_assigns = Map.put_new(conn_assigns, "flash", %{})

    Map.merge(session, conn_assigns)
  end

  @doc """
  Extracts the view module name (last part of module path).

  ## Examples

      iex> PhoenixDatastar.Helpers.get_view_name(MyApp.CounterStar)
      "CounterStar"
  """
  @spec get_view_name(module()) :: String.t()
  def get_view_name(view) when is_atom(view) do
    view |> Module.split() |> List.last()
  end

  @doc """
  Renders a view's template with the socket's assigns.
  """
  @spec render_html(module(), PhoenixDatastar.Socket.t()) :: Phoenix.HTML.Safe.t()
  def render_html(view, socket) do
    view.render(socket.assigns)
  end
end
