defmodule PhoenixDatastar.Helpers.JS do
  @moduledoc false
  # Shared JavaScript string escaping helpers

  @doc """
  Escapes a string for use in single-quoted JavaScript strings.
  """
  def escape_string(str) do
    str
    |> String.replace("\\", "\\\\")
    |> String.replace("'", "\\'")
    |> String.replace("\n", "\\n")
    |> String.replace("\r", "\\r")
  end
end
