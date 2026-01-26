defmodule PhoenixDatastar.SSETest do
  use ExUnit.Case

  alias PhoenixDatastar.SSE

  describe "new/1" do
    test "creates an SSE struct from a conn" do
      conn = %Plug.Conn{}
      sse = SSE.new(conn)

      assert %SSE{conn: ^conn, closed: false} = sse
    end
  end

  describe "closed?/1" do
    test "returns false for open connection" do
      sse = %SSE{conn: %Plug.Conn{}, closed: false}
      refute SSE.closed?(sse)
    end

    test "returns true for closed connection" do
      sse = %SSE{conn: %Plug.Conn{}, closed: true}
      assert SSE.closed?(sse)
    end
  end

  describe "close/1" do
    test "marks the connection as closed" do
      sse = %SSE{conn: %Plug.Conn{}, closed: false}
      sse = SSE.close(sse)

      assert SSE.closed?(sse)
    end
  end
end
