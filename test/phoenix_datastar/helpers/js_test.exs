defmodule PhoenixDatastar.Helpers.JSTest do
  use ExUnit.Case

  alias PhoenixDatastar.Helpers.JS

  describe "escape_string/1" do
    test "returns empty string unchanged" do
      assert JS.escape_string("") == ""
    end

    test "returns simple string unchanged" do
      assert JS.escape_string("hello world") == "hello world"
    end

    test "escapes single quotes" do
      assert JS.escape_string("it's") == "it\\'s"
      assert JS.escape_string("'quoted'") == "\\'quoted\\'"
      assert JS.escape_string("a'b'c") == "a\\'b\\'c"
    end

    test "escapes backslashes" do
      assert JS.escape_string("path\\to\\file") == "path\\\\to\\\\file"
      assert JS.escape_string("\\") == "\\\\"
      assert JS.escape_string("\\\\") == "\\\\\\\\"
    end

    test "escapes newlines" do
      assert JS.escape_string("line1\nline2") == "line1\\nline2"
      assert JS.escape_string("\n") == "\\n"
      assert JS.escape_string("a\nb\nc") == "a\\nb\\nc"
    end

    test "escapes carriage returns" do
      assert JS.escape_string("line1\rline2") == "line1\\rline2"
      assert JS.escape_string("\r") == "\\r"
      assert JS.escape_string("a\rb\rc") == "a\\rb\\rc"
    end

    test "escapes Windows-style line endings (CRLF)" do
      assert JS.escape_string("line1\r\nline2") == "line1\\r\\nline2"
    end

    test "handles multiple escape characters in combination" do
      # Single quotes and backslashes
      assert JS.escape_string("it's a \\path") == "it\\'s a \\\\path"

      # All special characters together
      assert JS.escape_string("a\\b'c\nd\re") == "a\\\\b\\'c\\nd\\re"
    end

    test "escapes backslashes before single quotes (order matters)" do
      # The backslash in \' should become \\' after escaping both
      assert JS.escape_string("\\'") == "\\\\\\'"
    end

    test "handles Unicode characters" do
      assert JS.escape_string("hello") == "hello"
      assert JS.escape_string("cafe") == "cafe"
      assert JS.escape_string("nihao") == "nihao"
    end

    test "handles URLs with special characters" do
      url = "https://example.com/path?name=O'Brien&redirect=true"
      assert JS.escape_string(url) == "https://example.com/path?name=O\\'Brien&redirect=true"
    end

    test "handles alert messages with quotes" do
      msg = "Error: File 'config.json' not found"
      assert JS.escape_string(msg) == "Error: File \\'config.json\\' not found"
    end

    test "handles multiline error messages" do
      msg = "Error occurred:\nLine 1: syntax error\nLine 2: missing token"
      expected = "Error occurred:\\nLine 1: syntax error\\nLine 2: missing token"
      assert JS.escape_string(msg) == expected
    end

    test "handles strings that look like escape sequences but aren't" do
      # The string contains literal backslash + n, not a newline
      # After escaping, backslash becomes \\, so \n becomes \\n
      assert JS.escape_string("\\n") == "\\\\n"
      assert JS.escape_string("\\r") == "\\\\r"
      assert JS.escape_string("\\'") == "\\\\\\'"
    end

    test "handles consecutive special characters" do
      assert JS.escape_string("''") == "\\'\\'"
      assert JS.escape_string("\n\n") == "\\n\\n"
      assert JS.escape_string("\r\r") == "\\r\\r"
      assert JS.escape_string("\\\\") == "\\\\\\\\"
    end

    test "preserves double quotes (not escaped)" do
      # Double quotes are not escaped as the function is designed for single-quoted JS strings
      assert JS.escape_string("say \"hello\"") == "say \"hello\""
    end

    test "handles very long strings" do
      long_string = String.duplicate("a'b\\c\n", 1000)
      result = JS.escape_string(long_string)

      # Verify the escaping is applied correctly throughout
      assert String.contains?(result, "\\'")
      assert String.contains?(result, "\\\\")
      assert String.contains?(result, "\\n")
      refute String.contains?(result, "\n")
    end

    test "handles strings with only special characters" do
      assert JS.escape_string("'''") == "\\'\\'\\'"
      assert JS.escape_string("\n\r\n") == "\\n\\r\\n"
    end

    test "handles tab characters (not escaped)" do
      # Tab is not escaped by this function
      assert JS.escape_string("a\tb") == "a\tb"
    end

    test "handles null character (not escaped)" do
      # Null byte is not escaped by this function
      assert JS.escape_string("a\0b") == "a\0b"
    end

    test "handles path with Windows backslashes and quotes" do
      path = "C:\\Users\\O'Brien\\Documents"
      expected = "C:\\\\Users\\\\O\\'Brien\\\\Documents"
      assert JS.escape_string(path) == expected
    end
  end
end
