defmodule PhoenixDatastar.DefaultHTMLTest do
  use ExUnit.Case, async: true

  alias PhoenixDatastar.DefaultHTML

  describe "mount/1" do
    test "renders a div with id 'app'" do
      assigns = build_assigns()
      result = render(assigns)

      assert result =~ ~s(id="app")
      assert result =~ "<div"
      assert result =~ "</div>"
    end

    test "renders data-signals with JSON-encoded session_id" do
      assigns = build_assigns(session_id: "test-session-123")
      result = render(assigns)

      assert result =~ "data-signals="
      # HTML entities are used in attributes, so quotes become &quot;
      assert result =~ "&quot;session_id&quot;:&quot;test-session-123&quot;"
    end

    test "renders data-signals with JSON-encoded event_path" do
      assigns = build_assigns(event_path: "/my-view/_event")
      result = render(assigns)

      assert result =~ "&quot;event_path&quot;:&quot;/my-view/_event&quot;"
    end

    test "renders data-signals with JSON-encoded nav_path" do
      assigns = build_assigns(nav_path: "/__datastar/nav")
      result = render(assigns)

      assert result =~ "&quot;nav_path&quot;:&quot;/__datastar/nav&quot;"
    end

    test "renders data-signals with JSON-encoded nav_token" do
      assigns = build_assigns(nav_token: "signed-token-abc")
      result = render(assigns)

      assert result =~ "&quot;nav_token&quot;:&quot;signed-token-abc&quot;"
    end

    test "merges initial_signals into data-signals" do
      assigns = build_assigns(initial_signals: %{count: 42, name: "Alice"})
      result = render(assigns)

      assert result =~ "&quot;count&quot;:42"
      assert result =~ "&quot;name&quot;:&quot;Alice&quot;"
    end

    test "handles empty initial_signals map" do
      assigns = build_assigns(initial_signals: %{})
      result = render(assigns)

      # Should still have framework signals
      assert result =~ "&quot;session_id&quot;:"
      assert result =~ "&quot;event_path&quot;:"
      assert result =~ "&quot;nav_path&quot;:"
      assert result =~ "&quot;nav_token&quot;:"
    end

    test "initial_signals are merged with framework signals" do
      assigns =
        build_assigns(
          session_id: "sess-123",
          event_path: "/test/_event",
          nav_path: "/__datastar/nav",
          nav_token: "token-xyz",
          initial_signals: %{user_count: 5}
        )

      result = render(assigns)

      # All signals should be present in the JSON
      assert result =~ "&quot;session_id&quot;:&quot;sess-123&quot;"
      assert result =~ "&quot;event_path&quot;:&quot;/test/_event&quot;"
      assert result =~ "&quot;nav_path&quot;:&quot;/__datastar/nav&quot;"
      assert result =~ "&quot;nav_token&quot;:&quot;token-xyz&quot;"
      assert result =~ "&quot;user_count&quot;:5"
    end

    test "renders data-init__once when stream_path is present" do
      assigns = build_assigns(stream_path: "/my-view/_stream")
      result = render(assigns)

      assert result =~ "data-init__once="
      # Single quotes are escaped as &#39; in HTML attributes
      assert result =~ "@get(&#39;/my-view/_stream&#39;, {openWhenHidden: true})"
    end

    test "does not render data-init__once when stream_path is nil" do
      assigns = build_assigns(stream_path: nil)
      result = render(assigns)

      refute result =~ "data-init__once"
    end

    test "renders inner_html content inside the div" do
      assigns = build_assigns(inner_html: {:safe, "<p>Hello World</p>"})
      result = render(assigns)

      assert result =~ "<p>Hello World</p>"
    end

    test "renders complex inner_html content" do
      complex_html =
        {:safe,
         """
         <header>
           <h1>Welcome</h1>
         </header>
         <main>
           <p>Content here</p>
         </main>
         """}

      assigns = build_assigns(inner_html: complex_html)
      result = render(assigns)

      assert result =~ "<header>"
      assert result =~ "<h1>Welcome</h1>"
      assert result =~ "<main>"
      assert result =~ "<p>Content here</p>"
    end

    test "renders empty inner_html" do
      assigns = build_assigns(inner_html: {:safe, ""})
      result = render(assigns)

      assert result =~ ~s(id="app")
      # Should still have opening and closing div
      assert result =~ "<div"
      assert result =~ "</div>"
    end

    test "handles initial_signals with nested maps" do
      assigns =
        build_assigns(
          initial_signals: %{
            user: %{name: "Bob", age: 30},
            settings: %{theme: "dark"}
          }
        )

      result = render(assigns)

      # Should properly JSON-encode nested structures
      assert result =~ "&quot;user&quot;:"
      assert result =~ "&quot;name&quot;:&quot;Bob&quot;"
      assert result =~ "&quot;age&quot;:30"
      assert result =~ "&quot;settings&quot;:"
      assert result =~ "&quot;theme&quot;:&quot;dark&quot;"
    end

    test "handles initial_signals with lists" do
      assigns = build_assigns(initial_signals: %{items: [1, 2, 3], tags: ["a", "b"]})
      result = render(assigns)

      assert result =~ "&quot;items&quot;:[1,2,3]"
      assert result =~ "&quot;tags&quot;:[&quot;a&quot;,&quot;b&quot;]"
    end

    test "handles initial_signals with boolean values" do
      assigns = build_assigns(initial_signals: %{enabled: true, visible: false})
      result = render(assigns)

      assert result =~ "&quot;enabled&quot;:true"
      assert result =~ "&quot;visible&quot;:false"
    end

    test "handles initial_signals with nil values" do
      assigns = build_assigns(initial_signals: %{optional: nil})
      result = render(assigns)

      assert result =~ "&quot;optional&quot;:null"
    end

    test "handles special characters in string signals" do
      assigns = build_assigns(initial_signals: %{message: "Hello \"World\" & <Friends>"})
      result = render(assigns)

      # JSON encoding should escape special characters, then HTML escapes the result
      assert result =~ "&quot;message&quot;:"
      # The HTML attribute will have the JSON-encoded string with double escaping
      assert result =~ "Hello"
    end

    test "stream_path with query parameters renders correctly" do
      assigns = build_assigns(stream_path: "/__datastar/stream?token=abc123")
      result = render(assigns)

      assert result =~ "@get(&#39;/__datastar/stream?token=abc123&#39;, {openWhenHidden: true})"
    end

    test "stream_path with ampersand is properly escaped" do
      assigns = build_assigns(stream_path: "/stream?foo=bar&baz=qux")
      result = render(assigns)

      assert result =~ "data-init__once="
      # Ampersand in HTML attribute is escaped
      assert result =~ "/stream?foo=bar&amp;baz=qux"
    end

    test "returns Phoenix.LiveView.Rendered struct" do
      assigns = build_assigns()
      result = DefaultHTML.mount(assigns)

      # Phoenix.LiveView.Rendered is the struct returned by ~H sigil
      assert %Phoenix.LiveView.Rendered{} = result
    end

    test "all framework signals are always present regardless of initial_signals content" do
      # Even if initial_signals has conflicting keys, framework signals should be there
      assigns =
        build_assigns(
          session_id: "correct-session",
          initial_signals: %{some_signal: "value"}
        )

      result = render(assigns)

      # Framework signals from the Map.merge (second arg wins for conflicts)
      assert result =~ "&quot;session_id&quot;:&quot;correct-session&quot;"
    end

    test "framework signals override initial_signals with same keys" do
      # Map.merge(@initial_signals, %{session_id: ...}) means framework signals win
      assigns =
        build_assigns(
          session_id: "framework-session",
          initial_signals: %{session_id: "user-session"}
        )

      result = render(assigns)

      # Framework signal should override user-provided one
      assert result =~ "&quot;session_id&quot;:&quot;framework-session&quot;"
      refute result =~ "&quot;session_id&quot;:&quot;user-session&quot;"
    end

    test "data-signals attribute contains valid JSON" do
      assigns =
        build_assigns(
          session_id: "test-123",
          event_path: "/test/_event",
          nav_path: "/__datastar/nav",
          nav_token: "token-abc",
          initial_signals: %{count: 5, name: "Test"}
        )

      result = render(assigns)

      # Extract the data-signals value and decode it
      [_, json_str] = Regex.run(~r/data-signals="([^"]+)"/, result)

      # Decode the HTML entities back to get the JSON
      json_str_decoded =
        json_str
        |> String.replace("&quot;", "\"")
        |> String.replace("&amp;", "&")
        |> String.replace("&lt;", "<")
        |> String.replace("&gt;", ">")

      # Should be valid JSON
      {:ok, decoded} = Jason.decode(json_str_decoded)

      # Verify all expected keys are present
      assert decoded["session_id"] == "test-123"
      assert decoded["event_path"] == "/test/_event"
      assert decoded["nav_path"] == "/__datastar/nav"
      assert decoded["nav_token"] == "token-abc"
      assert decoded["count"] == 5
      assert decoded["name"] == "Test"
    end

    test "data-init__once contains proper Datastar GET expression" do
      assigns = build_assigns(stream_path: "/test/_stream")
      result = render(assigns)

      # The expression should follow Datastar's action syntax
      assert result =~ "data-init__once="
      assert result =~ "@get("
      assert result =~ "openWhenHidden: true"
    end

    test "div wrapper structure is correct" do
      assigns = build_assigns(inner_html: {:safe, "<span>Content</span>"})
      result = render(assigns)

      # Check the basic structure
      assert result =~ ~r/<div[^>]*id="app"[^>]*>/
      assert result =~ "<span>Content</span>"
      assert result =~ "</div>"

      # Verify it's a single wrapping div (not nested divs from the template)
      div_open_count = length(Regex.scan(~r/<div/, result))
      div_close_count = length(Regex.scan(~r/<\/div>/, result))
      assert div_open_count == 1
      assert div_close_count == 1
    end
  end

  # Helper to build assigns with defaults
  defp build_assigns(overrides \\ []) do
    defaults = %{
      session_id: "default-session-id",
      stream_path: "/default/_stream",
      event_path: "/default/_event",
      nav_path: "/__datastar/nav",
      nav_token: "default-nav-token",
      initial_signals: %{},
      inner_html: {:safe, "<span>Default Content</span>"}
    }

    defaults
    |> Map.merge(Map.new(overrides))
    |> Map.put(:__changed__, nil)
  end

  # Helper to render the component and return the HTML string
  defp render(assigns) do
    assigns
    |> DefaultHTML.mount()
    |> Phoenix.HTML.Safe.to_iodata()
    |> IO.iodata_to_binary()
  end
end
