defmodule PhoenixDatastar.Socket do
  @moduledoc """
  Socket struct for PhoenixDatastar, similar to Phoenix.LiveView.Socket.
  Holds the view module, session id, assigns, signals, private data, and queued events.

  ## Assigns vs Signals

  - **Assigns** are server-side state, never sent to the client. Use `assign/2,3` and
    `update/3` to work with assigns. They are available in templates as `@key`.

  - **Signals** are Datastar reactive state sent to the client via SSE. Use `put_signal/2,3`
    and `update_signal/3` to work with signals. They must be JSON-serializable. The client
    accesses them via Datastar expressions like `$count`. Signals are **not** available
    as `@key` in templates — Datastar handles their rendering client-side.
  """

  alias PhoenixDatastar.Helpers.JS

  @enforce_keys [:view]
  defstruct [:id, :view, assigns: %{}, signals: %{}, private: %{}, events: []]

  @doc """
  Creates a new socket with standard assigns.

  ## Options

    * `:live` - Whether this is a live (stateful) view. Defaults to `true`.
      When `false`, `stream_path` is set to `nil`.
    * `:flash` - Flash map. Defaults to `%{}`.

  ## Examples

      Socket.new(session_id, MyApp.CounterStar, "/counter")
      Socket.new(session_id, MyApp.PageStar, "/about", live: false)
  """
  @spec new(String.t(), module(), String.t(), keyword()) :: t()
  def new(session_id, view, base_path, opts \\ []) do
    live? = Keyword.get(opts, :live, true)
    flash = Keyword.get(opts, :flash, %{})

    %__MODULE__{
      id: session_id,
      view: view,
      assigns: %{
        flash: flash,
        session_id: session_id,
        base_path: base_path,
        stream_path: if(live?, do: Path.join(base_path, "stream")),
        event_path: Path.join(base_path, "_event")
      }
    }
  end

  @type event ::
          {:patch, String.t(), String.t()}
          | {:script, String.t(), keyword()}

  @type t :: %__MODULE__{
          id: String.t() | nil,
          view: module(),
          assigns: map(),
          signals: map(),
          private: map(),
          events: list(event())
        }

  @doc """
  Assigns a single key-value pair to the socket's server-side assigns.

  Assigns are never sent to the client. Use `put_signal/3` for client-side
  Datastar signals.

  ## Examples

      assign(socket, :user, %User{name: "Alice"})
  """
  @spec assign(t(), atom(), any()) :: t()
  def assign(socket, key, value) when is_atom(key) do
    %{socket | assigns: Map.put(socket.assigns, key, value)}
  end

  @doc """
  Merges assigns into the socket from a map or keyword list.

  ## Examples

      assign(socket, %{user: user, settings: settings})
      assign(socket, user: user, settings: settings)
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

      update(socket, :user, &User.increment_visits/1)
  """
  @spec update(t(), atom(), (any() -> any())) :: t()
  def update(socket, key, fun) when is_atom(key) and is_function(fun, 1) do
    current = Map.get(socket.assigns, key)
    assign(socket, key, fun.(current))
  end

  @doc """
  Puts a single Datastar signal on the socket.

  Signals are sent to the client and must be JSON-serializable.
  They are accessed client-side via Datastar expressions (e.g., `$count`).

  ## Examples

      put_signal(socket, :count, 0)
  """
  @spec put_signal(t(), atom(), any()) :: t()
  def put_signal(socket, key, value) when is_atom(key) do
    %{socket | signals: Map.put(socket.signals, key, value)}
  end

  @doc """
  Merges signals into the socket from a map or keyword list.

  ## Examples

      put_signal(socket, %{count: 0, name: "test"})
      put_signal(socket, count: 0, name: "test")
  """
  @spec put_signal(t(), map() | keyword()) :: t()
  def put_signal(socket, new_signals) when is_map(new_signals) do
    %{socket | signals: Map.merge(socket.signals, new_signals)}
  end

  def put_signal(socket, new_signals) when is_list(new_signals) do
    %{socket | signals: Map.merge(socket.signals, Map.new(new_signals))}
  end

  @doc """
  Updates a signal using a function.

  ## Examples

      update_signal(socket, :count, &(&1 + 1))
  """
  @spec update_signal(t(), atom(), (any() -> any())) :: t()
  def update_signal(socket, key, fun) when is_atom(key) and is_function(fun, 1) do
    current = Map.get(socket.signals, key)
    put_signal(socket, key, fun.(current))
  end

  @doc """
  Queues an HTML patch to be sent via SSE.

  The selector is a CSS selector targeting the element to patch.
  The second argument can be either:
  - A render function that takes assigns and returns HTML
  - Raw HTML content (must implement Phoenix.HTML.Safe)

  The render function receives `socket.assigns` (server-side state only,
  not signals).

  ## Examples

  With a render function (recommended for pipelines):

      socket
      |> assign(:items, updated_items)
      |> patch_elements("#items", &render_items/1)
      |> then(&{:noreply, &1})

      defp render_items(assigns) do
        ~H|<ul id="items"><li :for={item <- @items}>{item}</li></ul>|
      end

  With raw HTML:

      socket
      |> patch_elements("#count", ~H"<span id=\"count\">42</span>")

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

    %{socket | events: socket.events ++ [{:patch, selector, html_binary}]}
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
    %{socket | events: socket.events ++ [{:script, script, opts}]}
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
