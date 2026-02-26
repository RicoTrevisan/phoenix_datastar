defmodule PhoenixDatastar.NavPlugTest do
  use ExUnit.Case, async: true

  import Phoenix.ConnTest
  import Plug.Conn

  test "falls back to hard reload script when soft navigation is not authorized" do
    conn =
      build_conn(:post, "/__datastar/nav", %{"to" => "/outside", "token" => "invalid"})
      |> Plug.Conn.put_private(:phoenix_endpoint, PhoenixDatastar.NavPlugTest.Endpoint)

    conn = PhoenixDatastar.NavPlug.call(conn, [])

    assert conn.status == 200
    assert get_resp_header(conn, "content-type") == ["text/event-stream; charset=utf-8"]
    assert conn.resp_body =~ "window.location='/outside'"
  end

  defmodule Endpoint do
    def config(:secret_key_base), do: String.duplicate("a", 64)
  end
end
