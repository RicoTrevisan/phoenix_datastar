defmodule PhoenixDatastar do
  @moduledoc """
  PhoenixDatastar view behaviour for building interactive web applications.

  ## Assigns vs Signals

  - **Assigns** (`assign/2,3`, `update/3`) are server-side state, never sent to the
    client. They are available in templates as `@key`. Use them for structs, DB records,
    or any data the server needs to remember.

  - **Signals** (`put_signal/2,3`, `update_signal/3`) are Datastar reactive state sent
    to the client via SSE. They must be JSON-serializable. The client accesses them via
    Datastar expressions like `$count`. Signals are **not** available as `@key` in
    templates — Datastar handles their rendering client-side.

  Client signals arrive as the `payload` argument to `handle_event/3`. They are untrusted
  input — read, validate, and explicitly `put_signal` what you want to send back.

  ## Usage

  For stateless views (no persistent connection):

      defmodule MyApp.CounterStar do
        use PhoenixDatastar

        @impl PhoenixDatastar
        def mount(_params, _session, socket) do
          {:ok, put_signal(socket, :count, 0)}
        end

        @impl PhoenixDatastar
        def handle_event("increment", payload, socket) do
          count = payload["count"] || 0
          {:noreply, put_signal(socket, :count, count + 1)}
        end

        @impl PhoenixDatastar
        def render(assigns) do
          ~H\"\"\"
          <div>
            <span data-text="$count"></span>
            <button data-on:click={event("increment")}>+</button>
          </div>
          \"\"\"
        end
      end

  For live views (with persistent SSE connection):

      defmodule MyApp.MultiplayerStar do
        use PhoenixDatastar, :live

        @impl PhoenixDatastar
        def mount(_params, _session, socket) do
          MyApp.PubSub.subscribe("updates")
          {:ok, socket}
        end

        @impl PhoenixDatastar
        def handle_info({:update, data}, socket) do
          {:noreply, patch_elements(socket, "#data", data_fragment(data))}
        end

        @impl PhoenixDatastar
        def terminate(socket) do
          MyApp.cleanup(socket.id)
          :ok
        end
      end
  """

  @callback mount(params :: map(), session :: map(), socket :: PhoenixDatastar.Socket.t()) ::
              {:ok, PhoenixDatastar.Socket.t()} | {:ok, PhoenixDatastar.Socket.t(), keyword()}

  @callback handle_event(
              event :: String.t(),
              payload :: map(),
              socket :: PhoenixDatastar.Socket.t()
            ) ::
              {:noreply, PhoenixDatastar.Socket.t()} | {:stop, PhoenixDatastar.Socket.t()}

  @callback handle_info(msg :: term(), socket :: PhoenixDatastar.Socket.t()) ::
              {:noreply, PhoenixDatastar.Socket.t()}

  @callback terminate(socket :: PhoenixDatastar.Socket.t()) :: :ok

  @callback render(assigns :: map()) :: Phoenix.HTML.Safe.t()

  @optional_callbacks [handle_info: 2, terminate: 1]

  @doc """
  Returns true if the given module is a live PhoenixDatastar view.

  A module is considered "live" if it was defined with `use PhoenixDatastar, :live`.
  Live views maintain a persistent SSE connection and GenServer state.

  ## Examples

      iex> PhoenixDatastar.live?(MyApp.StatelessStar)
      false

      iex> PhoenixDatastar.live?(MyApp.LiveStar)
      true
  """
  @spec live?(module()) :: boolean()
  def live?(module) do
    Code.ensure_compiled!(module)

    case module.__info__(:attributes)[:datastar_live] do
      [true] -> true
      _ -> false
    end
  end

  defmacro __using__(opts \\ []) do
    # Handle both `use PhoenixDatastar` and `use PhoenixDatastar, :live`
    live? =
      case opts do
        :live -> true
        [live: true] -> true
        _ -> false
      end

    quote do
      @behaviour PhoenixDatastar

      # Register and set the attribute for persistence
      Module.register_attribute(__MODULE__, :datastar_live, persist: true)
      @datastar_live unquote(live?)

      alias PhoenixDatastar.Socket
      import Socket
      import Phoenix.Component, only: [sigil_H: 2]

      @impl PhoenixDatastar
      def handle_event(_event, _payload, socket), do: {:noreply, socket}

      @impl PhoenixDatastar
      def handle_info(_msg, socket), do: {:noreply, socket}

      defoverridable handle_event: 3, handle_info: 2
    end
  end
end
