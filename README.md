# PhoenixDatastar

**A LiveView-like experience for Phoenix using Datastar's SSE + Signals architecture.**

> This is still in alpha, I'm figuring out the right apis.
> Comments and ideas welcome.

Build interactive Phoenix applications with [Datastar](https://data-star.dev/)'s simplicity: SSE instead of WebSockets, hypermedia over JSON, and a focus on performance.

## Installation

### With Igniter

If you have [Igniter](https://hex.pm/packages/igniter) installed, run:

```bash
mix igniter.install phoenix_datastar
```

This will automatically:
- Add the Registry to your supervision tree
- Enable stripping of debug annotations in dev
- Add the Datastar JavaScript to your layout
- Import the router macro
- Add `live_datastar` and `datastar` helpers to your web module

You'll then just need to add your routes (the installer will show you instructions).

### Manual Installation

Add `phoenix_datastar` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:phoenix_datastar, "~> 0.1.9"}
  ]
end
```

Then follow the setup steps below.

#### 1. Add Datastar to your layout

Include the Datastar JavaScript library in your layout's `<head>`:

```html
<script
  type="module"
  src="https://cdn.jsdelivr.net/gh/starfederation/datastar@1.0.0-RC.7/bundles/datastar.js"
></script>
```

#### 2. Add to your supervision tree

In your `application.ex`:

```elixir
children = [
  # ... other children
  {Registry, keys: :unique, name: PhoenixDatastar.Registry},
  # ... rest of your children
]
```

#### 3. Import the router macro

In your router:

```elixir
import PhoenixDatastar.Router

scope "/", MyAppWeb do
  pipe_through :browser

  datastar "/counter", CounterStar
end
```

#### 4. Create `:live_datastar` and `:datastar` in your `_web.ex`

```ex
defmodule MyAppWeb do
#... existing calls

  def live_datastar do
    quote do
      use PhoenixDatastar, :live
      import PhoenixDatastar.Actions

      unquote(html_helpers())
    end
  end

  def datastar do
    quote do
      use PhoenixDatastar
      import PhoenixDatastar.Actions

      unquote(html_helpers())
    end
  end
end
```

#### 5. Strip debug annotations in dev (optional)

In your `config/dev.exs`, enable stripping of LiveView debug annotations from SSE patches:

```elixir
config :phoenix_datastar, :strip_debug_annotations, true
```

This removes `<!-- @caller ... -->` comments and `data-phx-loc` attributes from SSE patches. The initial page load keeps annotations intact for debugging.

#### 6. Customize the mount template (optional)

PhoenixDatastar ships with a built-in mount template (`PhoenixDatastar.DefaultHTML`) that wraps your view content with the necessary Datastar signals and SSE initialization. **You don't need to create your own** — it works out of the box.

The default template automatically:
- Injects `session_id` as a Datastar signal
- Initializes all signals set via `put_signal` in `mount/3` as Datastar signals (via `@initial_signals`)
- Sets up the SSE stream connection for live views

If you need to customize it (e.g., add classes, extra attributes, or additional markup), create your own module:

```elixir
defmodule MyAppWeb.DatastarHTML do
  use Phoenix.Component

  def mount(assigns) do
    ~H"""
    <div
      id="app"
      class="my-wrapper"
      data-signals={Jason.encode!(Map.put(@initial_signals, :session_id, @session_id))}
      data-init__once={@stream_path && "@get('#{@stream_path}', {openWhenHidden: true})"}
    >
      {@inner_html}
    </div>
    """
  end
end
```

Available assigns in the mount template:
- `@session_id` — unique session identifier
- `@initial_signals` — map of signals set via `put_signal` in `mount/3`
- `@stream_path` — SSE stream URL (nil for stateless views)
- `@event_path` — event POST URL
- `@inner_html` — the rendered view content

Then configure it in `config/config.exs`:

```elixir
config :phoenix_datastar, :html_module, MyAppWeb.DatastarHTML
```

Or per-route:

```elixir
datastar "/custom", CustomStar, html_module: MyAppWeb.DatastarHTML
```


## Usage

### Assigns vs Signals

PhoenixDatastar separates server-side state from client-side reactive state:

- **Assigns** (`assign/2,3`, `update/3`) are server-side state. They are available in templates as `@key` and are **never sent to the client**. Use them for structs, DB records, or any data the server needs to remember or render HTML with.

- **Signals** (`put_signal/2,3`, `update_signal/3`) are Datastar reactive state sent to the client via SSE. They must be JSON-serializable. The client accesses them via Datastar expressions like `$count`. Signals are **not** available as `@key` in templates — Datastar handles their rendering client-side.

Client signals arrive as the `payload` argument in `handle_event/3`. They are untrusted input — read, validate, and explicitly `put_signal` what you want to send back.

### Basic Example: Signals

The simplest pattern uses Datastar signals for all client state. The count lives entirely in signals — Datastar renders it client-side via `data-text="$count"`:

```elixir
defmodule MyAppWeb.CounterStar do
  use MyAppWeb, :datastar
  # or: use PhoenixDatastar

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
    ~H"""
    <div>
      Count: <span data-text="$count"></span>
      <button data-on:click={event("increment")}>+</button>
    </div>
    """
  end
end
```

### Server-Rendered Patches with Assigns

For more complex rendering, use **assigns** for server-side state and **`patch_elements`** to push HTML updates. This is useful when you need HEEx templates, loops, or conditional logic that's easier to express server-side:

```elixir
defmodule MyAppWeb.ItemsStar do
  use MyAppWeb, :live_datastar
  # or: use PhoenixDatastar, :live

  @impl PhoenixDatastar
  def mount(_params, _session, socket) do
    {:ok, assign(socket, items: ["Alpha", "Bravo"])}
  end

  @impl PhoenixDatastar
  def handle_event("add", %{"name" => name}, socket) do
    {:noreply,
     socket
     |> update(:items, &(&1 ++ [name]))
     |> patch_elements("#items", &render_items/1)}
  end

  @impl PhoenixDatastar
  def render(assigns) do
    ~H"""
    <div>
      <ul id="items">
        <li :for={item <- @items}>{item}</li>
      </ul>
      <button data-on:click={event("add", "name: $newItem")}>Add</button>
    </div>
    """
  end

  defp render_items(assigns) do
    ~H"""
    <ul id="items">
      <li :for={item <- @items}>{item}</li>
    </ul>
    """
  end
end
```

> **Tip:** You can combine both patterns — use `put_signal` for simple reactive values
> (toggles, counters, form inputs) and `assign` + `patch_elements` for complex
> server-rendered sections.

## The Lifecycle

PhoenixDatastar uses a hybrid of request/response and streaming:

1. **Initial Page Load (HTTP)**: `GET /counter` calls `mount/3` and `render/1`, returns full HTML
2. **SSE Connection**: `GET /counter/stream` opens a persistent connection, starts a GenServer (live views only)
3. **User Interactions**: `POST /counter/_event/:event` triggers `handle_event/3`, updates pushed via SSE (live) or returned directly (stateless)

## Callbacks

| Callback | Purpose |
|----------|---------|
| `mount/3` | Initialize state on page load |
| `handle_event/3` | React to user actions |
| `handle_info/2` | Handle PubSub messages, timers, etc. |
| `render/1` | Render the full component |
| `terminate/1` | Cleanup on disconnect (optional) |

## Socket API

### Assigns (server-side state)

```elixir
# Assign values (server-side only, available as @key in templates)
socket = assign(socket, :user, current_user)
socket = assign(socket, items: [], loading: true)

# Update with a function
socket = update(socket, :count, &(&1 + 1))
```

### Signals (client-side Datastar state)

```elixir
# Set signals (sent to client, accessed as $key in Datastar expressions)
socket = put_signal(socket, :count, 0)
socket = put_signal(socket, count: 0, name: "test")

# Update a signal with a function
socket = update_signal(socket, :count, &(&1 + 1))
```

### DOM Patches

```elixir
# Queue a DOM patch (sent via SSE)
socket = patch_elements(socket, "#selector", &render_fn/1)
socket = patch_elements(socket, "#selector", ~H|<span>html</span>|)
```

### Scripts and Navigation

```elixir
# Execute JavaScript on the client
socket = execute_script(socket, "alert('Hello!')")
socket = execute_script(socket, "console.log('debug')", auto_remove: false)

# Redirect the client
socket = redirect(socket, "/dashboard")

# Log to the browser console
socket = console_log(socket, "Debug message")
socket = console_log(socket, "Warning!", level: :warn)
```

## Action Macros

PhoenixDatastar provides macros to simplify generating Datastar action expressions in your templates.

### Requirements

- `assigns.session_id` must be set in your template context (automatically set by PhoenixDatastar)
- `assigns.event_path` must be set (automatically set by PhoenixDatastar)
- A `<meta name="csrf-token">` tag must be present in your layout (Phoenix includes this by default)

### `event/2`

Generates a Datastar `@post` action for triggering server events.

```elixir
# Simple event
<button data-on:click={event("increment")}>+1</button>

# Event with options
<button data-on:click={event("toggle_code", "name: 'counter'")}>Toggle</button>

# With signals
<button data-on:click={event("update", "value: $count")}>Update</button>
```

## Stateless vs Live Views

```elixir
# Stateless view - no persistent connection, events handled synchronously
use MyAppWeb, :datastar
# or: use PhoenixDatastar

# Live view - persistent SSE connection with GenServer state
use MyAppWeb, :live_datastar
# or: use PhoenixDatastar, :live
```

**Stateless views** handle events synchronously — state is restored by calling `mount/3` on each request, client signals arrive in the payload, and the response is returned immediately. No GenServer or SSE connection is maintained.

**Live views** maintain a GenServer and SSE connection. Use `:live` when you need:
- Real-time updates from the server (PubSub, timers)
- Persistent server-side state across interactions
- `handle_info/2` callbacks

## Links

- [Datastar](https://data-star.dev/) - The frontend library this integrates with
- [Phoenix LiveView](https://hexdocs.pm/phoenix_live_view/) - The inspiration for the callback design

## License

MIT License - see [LICENSE](LICENSE) for details.
