defmodule PhoenixDatastar.StreamToken do
  @moduledoc false

  @salt "phoenix_datastar_stream"

  @doc false
  @spec sign(Plug.Conn.t(), map()) :: String.t()
  def sign(conn, payload) when is_map(payload) do
    Phoenix.Token.sign(endpoint!(conn), @salt, payload)
  end

  @doc false
  @spec verify(Plug.Conn.t(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def verify(conn, token, opts \\ []) when is_binary(token) do
    max_age =
      Keyword.get(
        opts,
        :max_age,
        Application.get_env(:phoenix_datastar, :stream_token_max_age, 3600)
      )

    Phoenix.Token.verify(endpoint!(conn), @salt, token, max_age: max_age)
  end

  defp endpoint!(conn) do
    conn.private[:phoenix_endpoint] || raise "Missing :phoenix_endpoint in conn.private"
  end
end
