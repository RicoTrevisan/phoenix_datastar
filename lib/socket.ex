defmodule PhoenixDatastar.Socket do
  @moduledoc """
  Socket struct for PhoenixDatastar, similar to Phoenix.LiveView.Socket.
  Holds the view module, session id, assigns, private data, and queued patches.
  """

  @enforce_keys [:view]
  defstruct [:id, :view, assigns: %{}, private: %{}, patches: []]

  @type t :: %__MODULE__{
          id: String.t() | nil,
          view: module(),
          assigns: map(),
          private: map(),
          patches: list({String.t(), String.t()})
        }

  @doc """
  Assigns a single key-value pair to the socket.

  ## Examples

      assign(socket, :count, 0)
  """
  @spec assign(t(), atom(), any()) :: t()
  def assign(socket, key, value) when is_atom(key) do
    %{socket | assigns: Map.put(socket.assigns, key, value)}
  end

  @doc """
  Merges assigns into the socket from a map or keyword list.

  ## Examples

      assign(socket, %{count: 0, name: "test"})
      assign(socket, count: 0, name: "test")
  """
  @spec assign(t(), map() | keyword()) :: t()
  def assign(socket, new_assigns) when is_map(new_assigns) do
    %{socket | assigns: Map.merge(socket.assigns, new_assigns)}
  end

  def assign(socket, new_assigns) when is_list(new_assigns) do
    %{socket | assigns: Map.merge(socket.assigns, Map.new(new_assigns))}
  end

  @doc """
  Updates an assign using a function.

  ## Examples

      update(socket, :count, &(&1 + 1))
  """
  @spec update(t(), atom(), (any() -> any())) :: t()
  def update(socket, key, fun) when is_atom(key) and is_function(fun, 1) do
    current = Map.get(socket.assigns, key)
    assign(socket, key, fun.(current))
  end

  @doc """
  Queues an HTML patch to be sent via SSE.

  The selector is a CSS selector targeting the element to patch.
  The second argument can be either:
  - A render function that takes assigns and returns HTML
  - Raw HTML content (must implement Phoenix.HTML.Safe)

  ## Examples

  With a render function (recommended for pipelines):

      socket
      |> update(:count, &(&1 + 1))
      |> patch_elements("#count", &render_count/1)
      |> then(&{:noreply, &1})

      defp render_count(assigns) do
        ~H|<span id="count">{@count}</span>|
      end

  With raw HTML:

      socket
      |> patch_elements("#count", ~H"<span id=\"count\">{@count}</span>")

  """
  @spec patch_elements(t(), String.t(), (map() -> Phoenix.HTML.Safe.t()) | Phoenix.HTML.Safe.t()) ::
          t()
  def patch_elements(socket, selector, render_fn)
      when is_binary(selector) and is_function(render_fn, 1) do
    html = render_fn.(socket.assigns)
    patch_elements_html(socket, selector, html)
  end

  def patch_elements(socket, selector, html) when is_binary(selector) do
    patch_elements_html(socket, selector, html)
  end

  defp patch_elements_html(socket, selector, html) do
    html_binary =
      html
      |> Phoenix.HTML.Safe.to_iodata()
      |> IO.iodata_to_binary()
      |> maybe_strip_debug_annotations()

    %{socket | patches: socket.patches ++ [{selector, html_binary}]}
  end

  @doc """
  Strips Phoenix LiveView debug annotations from HTML if they are enabled.

  Checks the LiveView config for `debug_heex_annotations` and `debug_attributes`
  and only strips when those features are enabled.
  """
  @spec maybe_strip_debug_annotations(String.t()) :: String.t()
  def maybe_strip_debug_annotations(html) when is_binary(html) do
    heex_annotations? = Application.get_env(:phoenix_datastar, :strip_heex_annotations, true)
    debug_attributes? = Application.get_env(:phoenix_datastar, :strip_debug_attributes, true)

    html
    |> maybe_strip_heex_comments(heex_annotations?)
    |> maybe_strip_debug_attributes(debug_attributes?)
  end

  defp maybe_strip_heex_comments(html, false), do: html

  defp maybe_strip_heex_comments(html, true) do
    html
    # Remove HEEx debug comments: <!-- @caller ... -->, <!-- <Component> ... -->, <!-- </Component> -->
    |> String.replace(~r/<!--\s*@caller\s+[^>]*-->/s, "")
    |> String.replace(~r/<!--\s*<[^>]+>\s+[^>]*-->/s, "")
    |> String.replace(~r/<!--\s*<\/[^>]+>\s*-->/s, "")
  end

  defp maybe_strip_debug_attributes(html, false), do: html

  defp maybe_strip_debug_attributes(html, true) do
    # Remove data-phx-loc attributes
    String.replace(html, ~r/\s*data-phx-loc="[^"]*"/, "")
  end
end
