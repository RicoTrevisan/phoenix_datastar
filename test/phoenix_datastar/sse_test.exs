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

  describe "format_event/2" do
    test "formats an event with a single data line" do
      result = SSE.format_event("test-event", ["hello"])

      assert result == "event: test-event\ndata: hello\n\n"
    end

    test "formats an event with multiple data lines" do
      result = SSE.format_event("datastar-patch-elements", [
        "selector #count",
        "mode outer",
        "elements <span>42</span>"
      ])

      expected = """
      event: datastar-patch-elements
      data: selector #count
      data: mode outer
      data: elements <span>42</span>

      """

      assert result == expected
    end

    test "formats signals event" do
      result = SSE.format_event("datastar-patch-signals", ["signals {\"count\": 5}"])

      assert result == "event: datastar-patch-signals\ndata: signals {\"count\": 5}\n\n"
    end
  end
end
