defmodule PhoenixDatastar.SSETest do
  use ExUnit.Case

  alias PhoenixDatastar.SSE

  defmodule MockConn do
    def chunked_conn(opts \\ []) do
      adapter = opts[:adapter] || {__MODULE__, %{chunks: []}}

      %Plug.Conn{
        adapter: adapter,
        state: :chunked
      }
    end

    def chunk(%{fail: true}, _chunk), do: {:error, :closed}

    def chunk(payload, chunk) do
      {:ok, chunk, Map.update(payload, :chunks, [chunk], &(&1 ++ [chunk]))}
    end
  end

  describe "new/1 and closed?/1 and close/1" do
    test "lifecycle: new creates open SSE, close marks it closed" do
      conn = %Plug.Conn{}
      sse = SSE.new(conn)

      assert %SSE{conn: ^conn, closed: false} = sse
      refute SSE.closed?(sse)

      closed = SSE.close(sse)
      assert SSE.closed?(closed)
    end
  end

  describe "send_event/4" do
    test "sends event and updates conn" do
      sse = SSE.new(MockConn.chunked_conn())

      assert {:ok, updated} = SSE.send_event(sse, "test-event", ["data"])
      assert %SSE{closed: false} = updated
      assert updated.conn != sse.conn
    end

    test "returns error when connection is closed" do
      sse = %SSE{conn: MockConn.chunked_conn(), closed: true}

      assert {:error, {:closed, ^sse}} = SSE.send_event(sse, "test-event", ["data"])
    end

    test "returns error when chunk fails" do
      conn = MockConn.chunked_conn(adapter: {MockConn, %{fail: true}})
      sse = SSE.new(conn)

      assert {:error, :closed} = SSE.send_event(sse, "test-event", ["data"])
    end

    test "accepts string data_lines and options" do
      sse = SSE.new(MockConn.chunked_conn())

      assert {:ok, _} = SSE.send_event(sse, "test", "single line", event_id: "e1", retry: 5000)
    end
  end

  describe "send_event!/4" do
    test "returns SSE on success, raises on failure" do
      sse = SSE.new(MockConn.chunked_conn())

      result =
        sse
        |> SSE.send_event!("event-1", ["data 1"])
        |> SSE.send_event!("event-2", ["data 2"])

      assert %SSE{closed: false} = result

      failed_sse = SSE.new(MockConn.chunked_conn(adapter: {MockConn, %{fail: true}}))

      assert_raise RuntimeError, ~r/Failed to send SSE event/, fn ->
        SSE.send_event!(failed_sse, "test-event", ["data"])
      end
    end
  end

  describe "format_event/2" do
    test "formats an event with a single data line" do
      result = SSE.format_event("test-event", ["hello"])

      assert result == "event: test-event\ndata: hello\n\n"
    end

    test "formats an event with multiple data lines" do
      result =
        SSE.format_event("datastar-patch-elements", [
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
