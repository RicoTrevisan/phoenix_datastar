defmodule PhoenixDatastar.Socket do
  @moduledoc """
  Socket struct for PhoenixDatastar, similar to Phoenix.LiveView.Socket.
  Holds the view module, session id, assigns, private data, queued patches, and queued scripts.
  """

  alias PhoenixDatastar.Helpers.JS

  @enforce_keys [:view]
  defstruct [:id, :view, assigns: %{}, private: %{}, patches: [], scripts: []]

  @type t :: %__MODULE__{
          id: String.t() | nil,
          view: module(),
          assigns: map(),
          private: map(),
          patches: list({String.t(), String.t()}),
          scripts: list({String.t(), keyword()})
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
  Queues a JavaScript script to be executed on the client via SSE.

  ## Options

  - `:auto_remove` - Remove script tag after execution (default: true)
  - `:attributes` - Map of additional script tag attributes

  ## Examples

      socket
      |> execute_script("alert('Hello!')")

      socket
      |> execute_script("console.log('debug')", auto_remove: false)

      # ES module script
      socket
      |> execute_script("import {...} from 'module'", attributes: %{type: "module"})

  """
  @spec execute_script(t(), String.t(), keyword()) :: t()
  def execute_script(socket, script, opts \\ []) when is_binary(script) do
    %{socket | scripts: socket.scripts ++ [{script, opts}]}
  end

  @doc """
  Queues a redirect to be executed on the client via SSE.

  Uses setTimeout for proper browser history handling, especially in Firefox.

  ## Options

  Same as `execute_script/3`.

  ## Examples

      socket
      |> redirect("/dashboard")

      socket
      |> redirect("https://example.com")

  """
  @spec redirect(t(), String.t(), keyword()) :: t()
  def redirect(socket, url, opts \\ []) when is_binary(url) do
    # Use setTimeout for proper browser history handling (especially Firefox)
    execute_script(socket, "setTimeout(function(){window.location='#{JS.escape_string(url)}'},0)", opts)
  end

  @doc """
  Queues a console.log to be executed on the client via SSE.

  ## Options

  - `:level` - Console method: `:log`, `:warn`, `:error`, `:info`, `:debug` (default: :log)
  - Plus all options from `execute_script/3`

  ## Examples

      socket
      |> console_log("Debug message")

      socket
      |> console_log("Warning!", level: :warn)

      socket
      |> console_log(%{user: "alice", action: "login"}, level: :info)

  """
  @spec console_log(t(), term(), keyword()) :: t()
  def console_log(socket, message, opts \\ []) do
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

    execute_script(socket, "console.#{level_str}(#{js_message})", opts)
  end

  @doc """
  Strips Phoenix LiveView debug annotations from HTML if configured.

  When `config :phoenix_datastar, :strip_debug_annotations, true` is set
  (typically in dev.exs), this removes:
  - HTML comments added by `debug_heex_annotations` (e.g., `<!-- @caller ... -->`)
  - `data-phx-loc` attributes added by `debug_attributes`

  This allows PhoenixDatastar SSE patches to work correctly even when LiveView
  debug annotations are enabled in development. The initial page load will still
  have annotations for debugging, but SSE patches will be clean.
  """
  @spec maybe_strip_debug_annotations(String.t()) :: String.t()
  def maybe_strip_debug_annotations(html) when is_binary(html) do
    if Application.get_env(:phoenix_datastar, :strip_debug_annotations, false) do
      html
      # Remove HEEx debug comments: <!-- @caller ... -->, <!-- <Component> ... -->, <!-- </Component> -->
      |> String.replace(~r/<!--\s*@caller\s+[^>]*-->/s, "")
      |> String.replace(~r/<!--\s*<[^>]+>\s+[^>]*-->/s, "")
      |> String.replace(~r/<!--\s*<\/[^>]+>\s*-->/s, "")
      # Remove data-phx-loc attributes
      |> String.replace(~r/\s*data-phx-loc="[^"]*"/, "")
    else
      html
    end
  end
end
