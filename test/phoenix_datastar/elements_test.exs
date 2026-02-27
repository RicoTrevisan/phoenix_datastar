defmodule PhoenixDatastar.ElementsTest do
  use ExUnit.Case, async: true

  alias PhoenixDatastar.Elements
  alias PhoenixDatastar.SSE

  # Helper to create a test SSE with a proper chunked connection
  defp create_test_sse do
    conn =
      Plug.Test.conn(:get, "/")
      |> Plug.Conn.put_resp_content_type("text/event-stream")
      |> Plug.Conn.send_chunked(200)

    SSE.new(conn)
  end

  # Helper to extract chunks sent to the connection
  defp get_chunks(sse) do
    # The chunks are stored in the adapter state
    {_adapter, state} = sse.conn.adapter
    state.chunks
  end

  describe "patch/3" do
    test "raises when selector option is missing" do
      sse = create_test_sse()

      assert_raise KeyError, ~r/:selector/, fn ->
        Elements.patch(sse, "<div>content</div>", [])
      end
    end

    test "raises ArgumentError for invalid mode" do
      sse = create_test_sse()

      assert_raise ArgumentError, ~r/Invalid patch mode: :invalid_mode/, fn ->
        Elements.patch(sse, "<div>content</div>", selector: "#target", mode: :invalid_mode)
      end
    end

    test "accepts all valid modes" do
      valid_modes = [:outer, :inner, :remove, :replace, :prepend, :append, :before, :after]

      for mode <- valid_modes do
        sse = create_test_sse()

        # Should not raise
        result = Elements.patch(sse, "<div>content</div>", selector: "#target", mode: mode)

        # Verify the mode was included in the chunks
        chunks = get_chunks(result)
        assert chunks =~ "mode #{mode}"
      end
    end

    test "uses default mode :outer when not specified" do
      sse = create_test_sse()

      result = Elements.patch(sse, "<div>content</div>", selector: "#target")

      chunks = get_chunks(result)
      assert chunks =~ "mode outer"
    end

    test "includes selector in data lines" do
      sse = create_test_sse()

      result = Elements.patch(sse, "<div>content</div>", selector: "#my-element")

      chunks = get_chunks(result)
      assert chunks =~ "data: selector #my-element"
    end

    test "includes HTML content as elements lines" do
      sse = create_test_sse()

      result = Elements.patch(sse, "<div>Hello World</div>", selector: "#target")

      chunks = get_chunks(result)
      assert chunks =~ "data: elements <div>Hello World</div>"
    end

    test "handles multiline HTML content" do
      sse = create_test_sse()

      html = """
      <div>
        <p>Line 1</p>
        <p>Line 2</p>
      </div>
      """

      result = Elements.patch(sse, html, selector: "#target")

      chunks = get_chunks(result)
      # Each line of HTML should be a separate elements line
      assert chunks =~ "data: elements <div>"
      assert chunks =~ "data: elements   <p>Line 1</p>"
      assert chunks =~ "data: elements   <p>Line 2</p>"
      assert chunks =~ "data: elements </div>"
    end

    test "does not include useViewTransition when false (default)" do
      sse = create_test_sse()

      result = Elements.patch(sse, "<div>content</div>", selector: "#target")

      chunks = get_chunks(result)
      refute chunks =~ "useViewTransition"
    end

    test "includes useViewTransition when true" do
      sse = create_test_sse()

      result =
        Elements.patch(sse, "<div>content</div>", selector: "#target", use_view_transitions: true)

      chunks = get_chunks(result)
      assert chunks =~ "data: useViewTransition true"
    end

    test "sends correct event type" do
      sse = create_test_sse()

      result = Elements.patch(sse, "<div>content</div>", selector: "#target")

      chunks = get_chunks(result)
      assert chunks =~ "event: datastar-patch-elements"
    end

    test "includes event_id when provided" do
      sse = create_test_sse()

      result = Elements.patch(sse, "<div>content</div>", selector: "#target", event_id: "evt-123")

      chunks = get_chunks(result)
      assert chunks =~ "id: evt-123"
    end

    test "includes retry when provided" do
      sse = create_test_sse()

      result = Elements.patch(sse, "<div>content</div>", selector: "#target", retry: 5000)

      chunks = get_chunks(result)
      assert chunks =~ "retry: 5000"
    end

    test "includes both event_id and retry when provided" do
      sse = create_test_sse()

      result =
        Elements.patch(sse, "<div>content</div>",
          selector: "#target",
          event_id: "evt-456",
          retry: 3000
        )

      chunks = get_chunks(result)
      assert chunks =~ "id: evt-456"
      assert chunks =~ "retry: 3000"
    end

    test "returns updated SSE struct" do
      sse = create_test_sse()

      result = Elements.patch(sse, "<div>content</div>", selector: "#target")

      assert %SSE{} = result
    end

    test "supports complex CSS selectors" do
      sse = create_test_sse()

      result =
        Elements.patch(sse, "<div>content</div>", selector: "div.container > ul li:first-child")

      chunks = get_chunks(result)
      assert chunks =~ "data: selector div.container > ul li:first-child"
    end

    test "handles empty HTML string" do
      sse = create_test_sse()

      result = Elements.patch(sse, "", selector: "#target")

      chunks = get_chunks(result)
      assert chunks =~ "data: elements "
    end

    test "handles HTML with special characters" do
      sse = create_test_sse()

      result = Elements.patch(sse, "<div>&amp; &lt;test&gt;</div>", selector: "#target")

      chunks = get_chunks(result)
      assert chunks =~ "data: elements <div>&amp; &lt;test&gt;</div>"
    end
  end

  describe "remove/3" do
    test "sends correct event type" do
      sse = create_test_sse()

      result = Elements.remove(sse, "#target")

      chunks = get_chunks(result)
      assert chunks =~ "event: datastar-patch-elements"
    end

    test "includes selector in data line" do
      sse = create_test_sse()

      result = Elements.remove(sse, "#element-to-remove")

      chunks = get_chunks(result)
      assert chunks =~ "data: selector #element-to-remove"
    end

    test "removes multiple elements with different selectors" do
      sse = create_test_sse()

      result1 = Elements.remove(sse, ".temporary")
      chunks1 = get_chunks(result1)
      assert chunks1 =~ "data: selector .temporary"

      result2 = Elements.remove(result1, "#old-content")
      chunks2 = get_chunks(result2)
      assert chunks2 =~ "data: selector #old-content"
    end

    test "includes event_id when provided" do
      sse = create_test_sse()

      result = Elements.remove(sse, "#target", event_id: "remove-123")

      chunks = get_chunks(result)
      assert chunks =~ "id: remove-123"
    end

    test "includes retry when provided" do
      sse = create_test_sse()

      result = Elements.remove(sse, "#target", retry: 2000)

      chunks = get_chunks(result)
      assert chunks =~ "retry: 2000"
    end

    test "returns updated SSE struct" do
      sse = create_test_sse()

      result = Elements.remove(sse, "#target")

      assert %SSE{} = result
    end

    test "supports complex CSS selectors" do
      sse = create_test_sse()

      result = Elements.remove(sse, "table.data tbody tr.highlighted")

      chunks = get_chunks(result)
      assert chunks =~ "data: selector table.data tbody tr.highlighted"
    end

    test "does not include mode line (unlike patch)" do
      sse = create_test_sse()

      result = Elements.remove(sse, "#target")

      chunks = get_chunks(result)
      # remove/3 only sends the selector, not a mode
      refute chunks =~ "data: mode"
    end
  end

  describe "chaining operations" do
    test "can chain multiple patch calls" do
      sse = create_test_sse()

      result =
        sse
        |> Elements.patch("<div>First</div>", selector: "#a")
        |> Elements.patch("<div>Second</div>", selector: "#b")
        |> Elements.patch("<div>Third</div>", selector: "#c")

      chunks = get_chunks(result)
      assert chunks =~ "selector #a"
      assert chunks =~ "selector #b"
      assert chunks =~ "selector #c"
    end

    test "can chain patch and remove calls" do
      sse = create_test_sse()

      result =
        sse
        |> Elements.patch("<div>New content</div>", selector: "#update")
        |> Elements.remove("#delete")
        |> Elements.patch("<span>More</span>", selector: "#another", mode: :append)

      chunks = get_chunks(result)
      assert chunks =~ "selector #update"
      assert chunks =~ "elements <div>New content</div>"
      assert chunks =~ "selector #delete"
      assert chunks =~ "selector #another"
      assert chunks =~ "mode append"
    end
  end
end
