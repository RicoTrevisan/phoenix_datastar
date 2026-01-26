defmodule PhoenixDatastar.Scripts do
  @moduledoc """
  Functions for executing JavaScript on the client.

  This module provides utilities for sending JavaScript to execute
  in the browser through Server-Sent Events.

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

  alias PhoenixDatastar.SSE

  # Event type for script execution
  @event_type "datastar-execute-script"

  # Default values
  @default_auto_remove true

  @doc """
  Executes JavaScript on the client.

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
  @spec execute(SSE.t(), String.t(), keyword()) :: SSE.t()
  def execute(sse, script, opts \\ []) when is_binary(script) do
    auto_remove = Keyword.get(opts, :auto_remove, @default_auto_remove)
    attributes = Keyword.get(opts, :attributes, %{})

    data_lines =
      []
      |> maybe_add_auto_remove(auto_remove)
      |> maybe_add_attributes(attributes)
      |> add_script_lines(script)

    event_opts =
      [
        event_id: opts[:event_id],
        retry: opts[:retry]
      ]
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)

    SSE.send_event!(sse, @event_type, data_lines, event_opts)
  end

  @doc """
  Redirects the browser to a new URL.

  ## Options

  Same as `execute/3`.

  ## Examples

      sse |> redirect("/dashboard")
      sse |> redirect("https://example.com")

  """
  @spec redirect(SSE.t(), String.t(), keyword()) :: SSE.t()
  def redirect(sse, url, opts \\ []) when is_binary(url) do
    execute(sse, "window.location = '#{escape_js_string(url)}'", opts)
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
  @spec console_log(SSE.t(), term(), keyword()) :: SSE.t()
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
        msg when is_binary(msg) -> "'#{escape_js_string(msg)}'"
        msg -> Jason.encode!(msg)
      end

    execute(sse, "console.#{level_str}(#{js_message})", opts)
  end

  # Private helpers

  defp maybe_add_auto_remove(lines, true), do: lines

  defp maybe_add_auto_remove(lines, false) do
    lines ++ ["autoRemove false"]
  end

  defp maybe_add_attributes(lines, attributes) when map_size(attributes) == 0, do: lines

  defp maybe_add_attributes(lines, attributes) do
    attr_lines =
      attributes
      |> Enum.map(fn {key, value} -> "attributes #{key} #{value}" end)

    lines ++ attr_lines
  end

  defp add_script_lines(lines, script) do
    script_lines =
      script
      |> String.split("\n")
      |> Enum.map(&("script " <> &1))

    lines ++ script_lines
  end

  defp escape_js_string(str) do
    str
    |> String.replace("\\", "\\\\")
    |> String.replace("'", "\\'")
    |> String.replace("\n", "\\n")
    |> String.replace("\r", "\\r")
  end
end
