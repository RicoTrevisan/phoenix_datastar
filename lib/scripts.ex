defmodule PhoenixDatastar.Scripts do
  @moduledoc """
  Functions for executing JavaScript on the client.

  This module provides utilities for sending JavaScript to execute
  in the browser through Server-Sent Events.

  Internally, this uses `datastar-patch-elements` to append a `<script>` tag
  to the body, which is the approach used by the official Datastar SDKs.

  ## Executing Scripts

  Send JavaScript to run on the client:

      sse
      |> PhoenixDatastar.Scripts.execute("alert('Hello!')")

      # Keep script tag in DOM (default auto-removes after execution)
      sse
      |> PhoenixDatastar.Scripts.execute("console.log('debug')", auto_remove: false)

      # With script attributes (e.g., ES modules)
      sse
      |> PhoenixDatastar.Scripts.execute("import {...}", attributes: %{type: "module"})

  ## Convenience Functions

  Common script operations have dedicated helpers:

      sse
      |> PhoenixDatastar.Scripts.redirect("/dashboard")

      sse
      |> PhoenixDatastar.Scripts.console_log("Debug info", level: :warn)

  """

  alias PhoenixDatastar.Elements
  alias PhoenixDatastar.Helpers.JS

  @doc """
  Executes JavaScript on the client by appending a script tag to the body.

  ## Options

  - `:auto_remove` - Remove script tag after execution (default: true)
  - `:attributes` - Map of additional script tag attributes
  - `:event_id` - Event ID for client tracking
  - `:retry` - Retry duration in milliseconds

  ## Examples

      # Simple script execution
      sse |> execute("alert('Hello!')")

      # Keep script in DOM
      sse |> execute("window.myVar = 42", auto_remove: false)

      # ES module script
      sse |> execute("import {...} from 'module'", attributes: %{type: "module"})

  """
  @spec execute(PhoenixDatastar.SSE.t(), String.t(), keyword()) :: PhoenixDatastar.SSE.t()
  def execute(sse, script, opts \\ []) when is_binary(script) do
    auto_remove = Keyword.get(opts, :auto_remove, true)
    attributes = Keyword.get(opts, :attributes, %{})

    # Build script tag attributes
    attr_list =
      attributes
      |> Map.to_list()
      |> Enum.map(fn {k, v} -> ~s(#{k}="#{escape_html_attr(v)}") end)

    attrs_str = if attr_list == [], do: "", else: " " <> Enum.join(attr_list, " ")

    # For auto-remove, wrap script to remove itself after execution
    # (onload doesn't work for inline scripts, only external ones)
    final_script =
      if auto_remove do
        "(function(){#{script}})();document.currentScript.remove();"
      else
        script
      end

    # Build the script tag
    script_html = "<script#{attrs_str}>#{escape_script_content(final_script)}</script>"

    # Use patch-elements to append the script to body
    element_opts =
      [
        selector: "body",
        mode: :append,
        event_id: opts[:event_id],
        retry: opts[:retry]
      ]
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)

    Elements.patch(sse, script_html, element_opts)
  end

  @doc """
  Redirects the browser to a new URL.

  ## Options

  Same as `execute/3`.

  ## Examples

      sse |> redirect("/dashboard")
      sse |> redirect("https://example.com")

  """
  @spec redirect(PhoenixDatastar.SSE.t(), String.t(), keyword()) :: PhoenixDatastar.SSE.t()
  def redirect(sse, url, opts \\ []) when is_binary(url) do
    # Use setTimeout to ensure proper browser history handling (especially in Firefox)
    execute(sse, "setTimeout(function(){window.location='#{JS.escape_string(url)}'},0)", opts)
  end

  @doc """
  Logs a message to the browser console.

  ## Options

  - `:level` - Console method to use: `:log`, `:warn`, `:error`, `:info`, `:debug` (default: :log)
  - Plus all options from `execute/3`

  ## Examples

      sse |> console_log("Debug message")
      sse |> console_log("Warning!", level: :warn)
      sse |> console_log(%{user: "alice", action: "login"}, level: :info)

  """
  @spec console_log(PhoenixDatastar.SSE.t(), term(), keyword()) :: PhoenixDatastar.SSE.t()
  def console_log(sse, message, opts \\ []) do
    {level, opts} = Keyword.pop(opts, :level, :log)

    level_str =
      case level do
        :log -> "log"
        :warn -> "warn"
        :error -> "error"
        :info -> "info"
        :debug -> "debug"
        _ -> "log"
      end

    js_message =
      case message do
        msg when is_binary(msg) -> "'#{JS.escape_string(msg)}'"
        msg -> Jason.encode!(msg)
      end

    execute(sse, "console.#{level_str}(#{js_message})", opts)
  end

  # Private helpers

  defp escape_html_attr(str) when is_binary(str) do
    str
    |> String.replace("&", "&amp;")
    |> String.replace("\"", "&quot;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end

  defp escape_html_attr(other), do: to_string(other)

  defp escape_script_content(script) do
    # Escape </script> to prevent premature tag closing
    String.replace(script, "</script>", "<\\/script>")
  end
end
