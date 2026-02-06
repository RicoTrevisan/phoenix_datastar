defmodule PhoenixDatastar.Helpers do
  @moduledoc """
  Shared helper functions for PhoenixDatastar modules.
  """

  @doc """
  Extracts the session map from a Plug.Conn.

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

    # Include current_user from conn assigns if available
    if conn.assigns[:current_user] do
      Map.put(session, "current_user", conn.assigns[:current_user])
    else
      session
    end
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
  Renders a view's template.
  """
  @spec render_html(module(), PhoenixDatastar.Socket.t()) :: Phoenix.HTML.Safe.t()
  def render_html(view, socket) do
    view.render(socket.assigns)
  end

  @doc """
  Internal assigns that should be filtered from signals.
  """
  @spec internal_assigns() :: [atom()]
  def internal_assigns, do: [:session_id, :base_path, :stream_path, :event_path]

  @doc """
  Filters internal assigns from a map, returning only user-defined signals.
  """
  @spec user_signals(map()) :: map()
  def user_signals(assigns) do
    Map.drop(assigns, internal_assigns())
  end
end
