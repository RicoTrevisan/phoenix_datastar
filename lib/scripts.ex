defmodule PhoenixDatastar.Scripts do
  @moduledoc """
  Executes JavaScript on the client via SSE.

  Appends a `<script>` tag to the body using `datastar-patch-elements`.

      sse |> execute("alert('Hello!')")
      sse |> execute("console.log('debug')", auto_remove: false)
  """

  alias PhoenixDatastar.Elements

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
