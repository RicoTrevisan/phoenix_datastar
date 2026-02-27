defmodule PhoenixDatastar.RouteRegistry do
  @moduledoc """
  Runtime route lookup helpers for PhoenixDatastar session-aware routing.

  This module matches request paths against the route metadata compiled by
  `PhoenixDatastar.Router.datastar/3`. Each router that uses `datastar/3`
  generates a `__phoenix_datastar_routes__/0` function at compile time,
  which this module reads at runtime.

  Used internally by `PhoenixDatastar.NavPlug` to resolve navigation targets
  and verify session membership during soft navigation.
  """

  @type route_match :: %{datastar: map(), path_params: map()} | nil

  @doc """
  Matches a request path against registered Datastar routes.

  Returns a map with `:datastar` (the route metadata including `:view`,
  `:session_name`, `:root_selector`, etc.) and `:path_params` (extracted
  dynamic segments), or `nil` if no route matches.

  The `method` and `host` parameters are accepted for future use but are
  currently ignored — all registered routes are matched regardless.
  """
  @spec match(module(), String.t(), String.t(), String.t()) :: route_match()
  def match(router, method, path, host \\ "localhost")
      when is_atom(router) and is_binary(method) and is_binary(path) do
    _ = {method, host}

    router
    |> routes()
    |> Enum.find_value(fn datastar ->
      case match_path(datastar.path, path) do
        {:ok, path_params} -> %{datastar: datastar, path_params: path_params}
        :error -> nil
      end
    end)
  end

  @doc """
  Returns the `datastar_session` name for a matched route, or `nil`.

  Convenience wrapper around `match/4` that extracts just the session name.
  """
  @spec session_name(module(), String.t(), String.t(), String.t()) :: atom() | nil
  def session_name(router, method, path, host \\ "localhost") do
    case match(router, method, path, host) do
      %{datastar: %{session_name: name}} -> name
      _ -> nil
    end
  end

  defp routes(router) do
    if function_exported?(router, :__phoenix_datastar_routes__, 0) do
      router.__phoenix_datastar_routes__()
    else
      []
    end
  end

  defp match_path(pattern, path) do
    pattern_segments = split_path(pattern)
    path_segments = split_path(path)

    if length(pattern_segments) == length(path_segments) do
      match_segments(pattern_segments, path_segments, %{})
    else
      :error
    end
  end

  defp split_path(path), do: path |> String.trim_leading("/") |> String.split("/", trim: true)

  defp match_segments([], [], params), do: {:ok, params}

  defp match_segments([":" <> key | rest_pattern], [value | rest_path], params) do
    match_segments(rest_pattern, rest_path, Map.put(params, key, value))
  end

  defp match_segments([segment | rest_pattern], [segment | rest_path], params) do
    match_segments(rest_pattern, rest_path, params)
  end

  defp match_segments(_pattern, _path, _params), do: :error
end
