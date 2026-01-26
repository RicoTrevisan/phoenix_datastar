defmodule PhoenixDatastar.Elements do
  @moduledoc """
  Functions for patching and removing DOM elements.

  This module provides utilities for updating HTML content on the client
  through Server-Sent Events.

  ## Patching Elements

  Update DOM elements with new HTML content:

      sse
      |> PhoenixDatastar.Elements.patch("<div>New content</div>", selector: "#target")

  ## Patch Modes

  - `:outer` - Replace the entire element (default)
  - `:inner` - Replace only the inner HTML
  - `:prepend` - Insert content at the beginning of the element's children
  - `:append` - Insert content at the end of the element's children
  - `:before` - Insert content before the element
  - `:after` - Insert content after the element
  - `:replace` - Replace the element with new content

  ## Removing Elements

  Remove elements from the DOM:

      sse
      |> PhoenixDatastar.Elements.remove("#target")
      |> PhoenixDatastar.Elements.remove_by_id("my-element")

  """

  alias PhoenixDatastar.SSE

  # Event type for element patches
  @event_type "datastar-patch-elements"

  # Default values
  @default_patch_mode :outer
  @default_use_view_transitions false

  # Valid patch modes
  @valid_modes ~w(outer inner remove replace prepend append before after)a

  @doc """
  Patches DOM elements with new HTML content.

  ## Options

  - `:selector` - CSS selector for target elements (required)
  - `:mode` - Patch mode (default: :outer)
  - `:use_view_transitions` - Enable View Transitions API (default: false)
  - `:event_id` - Event ID for client tracking
  - `:retry` - Retry duration in milliseconds

  ## Examples

      # Replace entire element
      sse |> patch("<div>Content</div>", selector: "#target")

      # Update inner HTML only
      sse |> patch("<p>New text</p>", selector: ".content", mode: :inner)

      # Append to element
      sse |> patch("<li>Item</li>", selector: "ul", mode: :append)

      # With view transitions
      sse |> patch("<div>Smooth</div>", selector: "#box", use_view_transitions: true)

  """
  @spec patch(SSE.t(), String.t(), keyword()) :: SSE.t()
  def patch(sse, html, opts \\ []) when is_binary(html) do
    selector = Keyword.fetch!(opts, :selector)
    mode = Keyword.get(opts, :mode, @default_patch_mode)
    use_view_transitions = Keyword.get(opts, :use_view_transitions, @default_use_view_transitions)

    unless mode in @valid_modes do
      raise ArgumentError, "Invalid patch mode: #{inspect(mode)}"
    end

    data_lines =
      []
      |> add_selector(selector)
      |> add_mode(mode)
      |> maybe_add_view_transitions(use_view_transitions)
      |> add_elements(html)

    event_opts =
      [
        event_id: opts[:event_id],
        retry: opts[:retry]
      ]
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)

    SSE.send_event!(sse, @event_type, data_lines, event_opts)
  end

  @doc """
  Patches elements with formatted HTML using interpolation.

  ## Example

      sse
      |> patchf(
        ~s(<div class="user">%{name} - %{email}</div>),
        [name: "Alice", email: "alice@example.com"],
        selector: "#user-info"
      )

  """
  @spec patchf(SSE.t(), String.t(), keyword(), keyword()) :: SSE.t()
  def patchf(sse, format, values, opts) do
    html = :io_lib.format(to_charlist(format), values) |> to_string()
    patch(sse, html, opts)
  end

  @doc """
  Patches elements by ID.

  Convenience function for patching with an ID selector.

  ## Example

      sse |> patch_by_id("my-element", "<div>Content</div>")

  """
  @spec patch_by_id(SSE.t(), String.t(), String.t(), keyword()) :: SSE.t()
  def patch_by_id(sse, id, html, opts \\ []) do
    opts = Keyword.put(opts, :selector, "##{id}")
    patch(sse, html, opts)
  end

  @doc """
  Removes elements from the DOM by selector.

  ## Options

  - `:event_id` - Event ID for client tracking
  - `:retry` - Retry duration in milliseconds

  ## Example

      sse
      |> PhoenixDatastar.Elements.remove(".temporary")
      |> PhoenixDatastar.Elements.remove("#old-content")

  """
  @spec remove(SSE.t(), String.t(), keyword()) :: SSE.t()
  def remove(sse, selector, opts \\ []) when is_binary(selector) do
    data_lines = ["selector " <> selector]

    event_opts =
      [
        event_id: opts[:event_id],
        retry: opts[:retry]
      ]
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)

    SSE.send_event!(sse, @event_type, data_lines, event_opts)
  end

  @doc """
  Removes an element by ID.

  Convenience function equivalent to calling `remove/3` with an ID selector.

  ## Example

      sse |> remove_by_id("temporary-message")

  """
  @spec remove_by_id(SSE.t(), String.t(), keyword()) :: SSE.t()
  def remove_by_id(sse, id, opts \\ []) do
    remove(sse, "##{id}", opts)
  end

  # Convenience functions for patch modes

  @doc "Patches with :outer mode (replaces entire element)"
  def patch_outer(sse, html, opts), do: patch(sse, html, Keyword.put(opts, :mode, :outer))

  @doc "Patches with :inner mode (replaces inner HTML)"
  def patch_inner(sse, html, opts), do: patch(sse, html, Keyword.put(opts, :mode, :inner))

  @doc "Patches with :prepend mode (inserts at beginning)"
  def patch_prepend(sse, html, opts), do: patch(sse, html, Keyword.put(opts, :mode, :prepend))

  @doc "Patches with :append mode (inserts at end)"
  def patch_append(sse, html, opts), do: patch(sse, html, Keyword.put(opts, :mode, :append))

  @doc "Patches with :before mode (inserts before element)"
  def patch_before(sse, html, opts), do: patch(sse, html, Keyword.put(opts, :mode, :before))

  @doc "Patches with :after mode (inserts after element)"
  def patch_after(sse, html, opts), do: patch(sse, html, Keyword.put(opts, :mode, :after))

  @doc "Patches with :replace mode (replaces element)"
  def patch_replace(sse, html, opts), do: patch(sse, html, Keyword.put(opts, :mode, :replace))

  # Private helpers

  defp add_selector(lines, selector) do
    lines ++ ["selector " <> selector]
  end

  defp add_mode(lines, mode) do
    lines ++ ["mode " <> to_string(mode)]
  end

  defp maybe_add_view_transitions(lines, false), do: lines

  defp maybe_add_view_transitions(lines, true) do
    lines ++ ["useViewTransition true"]
  end

  defp add_elements(lines, html) do
    html_lines =
      html
      |> String.split("\n")
      |> Enum.map(&("elements " <> &1))

    lines ++ html_lines
  end
end
