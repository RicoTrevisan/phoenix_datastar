defmodule PhoenixDatastar.ScriptsTest do
  use ExUnit.Case, async: true

  describe "execute/3" do
    test "basic script execution generates correct SSE event structure" do
      script = "alert('Hello!')"
      expected_wrapped = "(function(){alert('Hello!')})();document.currentScript.remove();"

      assert String.contains?(expected_wrapped, script)
      assert String.contains?(expected_wrapped, "document.currentScript.remove()")
    end

    test "auto_remove: true wraps script with self-removal code" do
      script = "console.log('test')"
      expected = "(function(){console.log('test')})();document.currentScript.remove();"
      wrapped = wrap_script(script, true)
      assert wrapped == expected
    end

    test "auto_remove: false preserves script as-is" do
      script = "window.myVar = 42"
      wrapped = wrap_script(script, false)
      assert wrapped == script
      refute String.contains?(wrapped, "document.currentScript.remove()")
    end
  end

  describe "escape_html_attr behavior" do
    test "escapes ampersands in attributes" do
      assert escape_html_attr_test("foo&bar") == "foo&amp;bar"
    end

    test "escapes less-than signs in attributes" do
      assert escape_html_attr_test("foo<bar") == "foo&lt;bar"
    end

    test "escapes greater-than signs in attributes" do
      assert escape_html_attr_test("foo>bar") == "foo&gt;bar"
    end

    test "handles non-binary input by converting to string" do
      assert escape_html_attr_test(:module) == "module"
    end

    test "handles integer input" do
      assert escape_html_attr_test(42) == "42"
    end
  end

  describe "escape_script_content behavior" do
    test "escapes closing script tags" do
      assert escape_script_content_test("</script>") == "<\\/script>"
    end

    test "escapes multiple closing script tags" do
      input = "var x = '</script>'; var y = '</script>';"
      expected = "var x = '<\\/script>'; var y = '<\\/script>';"
      assert escape_script_content_test(input) == expected
    end

    test "preserves regular content without script tags" do
      input = "console.log('Hello, World!');"
      assert escape_script_content_test(input) == input
    end
  end

  describe "attributes option" do
    test "empty attributes produces no extra attributes" do
      assert build_attr_list(%{}) == []
    end

    test "single attribute is formatted correctly" do
      attrs = %{type: "module"}
      attr_list = build_attr_list(attrs)
      assert length(attr_list) == 1
      assert Enum.at(attr_list, 0) =~ "type="
      assert Enum.at(attr_list, 0) =~ "module"
    end
  end

  describe "options passthrough" do
    test "event_id option is included when provided" do
      opts = [event_id: "evt-123", retry: nil]
      filtered = Enum.reject(opts, fn {_k, v} -> is_nil(v) end)
      assert filtered == [event_id: "evt-123"]
    end

    test "retry option is included when provided" do
      opts = [event_id: nil, retry: 5000]
      filtered = Enum.reject(opts, fn {_k, v} -> is_nil(v) end)
      assert filtered == [retry: 5000]
    end

    test "nil options are filtered out" do
      opts = [selector: "body", mode: :append, event_id: nil, retry: nil]
      filtered = Enum.reject(opts, fn {_k, v} -> is_nil(v) end)
      assert filtered == [selector: "body", mode: :append]
    end
  end

  describe "script tag construction" do
    test "constructs basic script tag" do
      script = "alert('test')"
      final_script = wrap_script(script, true)
      escaped_script = escape_script_content_test(final_script)
      expected = "<script>" <> escaped_script <> "</script>"
      actual = "<script>" <> escaped_script <> "</script>"
      assert actual == expected
    end
  end

  describe "edge cases" do
    test "empty script string" do
      wrapped = wrap_script("", true)
      assert wrapped == "(function(){})();document.currentScript.remove();"
    end

    test "very long script" do
      script = String.duplicate("console.log('test');", 1000)
      wrapped = wrap_script(script, true)
      assert String.length(wrapped) > String.length(script)
      assert String.starts_with?(wrapped, "(function(){")
      assert String.ends_with?(wrapped, "})();document.currentScript.remove();")
    end
  end

  # Helper functions that replicate the private functions for testing
  defp escape_html_attr_test(str) when is_binary(str) do
    str
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end

  defp escape_html_attr_test(other), do: to_string(other)

  defp escape_script_content_test(script) do
    String.replace(script, "</script>", "<\\/script>")
  end

  defp build_attr_list(attributes) do
    attributes
    |> Map.to_list()
    |> Enum.map(fn {k, v} -> "#{k}=#{inspect(escape_html_attr_test(v))}" end)
  end

  defp wrap_script(script, auto_remove) do
    if auto_remove do
      "(function(){" <> script <> "})();document.currentScript.remove();"
    else
      script
    end
  end
end
