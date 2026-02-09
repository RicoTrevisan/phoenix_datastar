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
- Add `live_sse` and `datastar` helpers to your web module

You'll then just need to add your routes (the installer will show you instructions).

### Manual Installation

Add `phoenix_datastar` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:phoenix_datastar, "~> 0.1.4"}
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

#### 4. Create `:live_sse` and `:datastar` in your `_web.ex`

```ex
defmodule MyAppWeb do
#... existing calls

  def live_sse do
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
- Initializes all assigns from `mount/3` as Datastar signals (via `@initial_signals`)
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
- `@initial_signals` — map of user-defined assigns from `mount/3` (internal assigns like `base_path` are filtered out)
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

### Basic Example

```elixir
defmodule MyAppWeb.CounterStar do
  use MyAppWeb, :live_sse
  # if not present in `my_app_web.ex` file use
  # `use PhoenixDatastar, :live`

  @impl PhoenixDatastar
  def mount(_params, _session, socket) do
    # Assigns are automatically initialized as Datastar signals —
    # no need to manually add data-signals in your template
    {:ok, assign(socket, count: 0)}
  end

  @impl PhoenixDatastar
  def handle_event("increment", _payload, socket) do
    {:noreply,
     socket
     |> update(:count, &(&1 + 1))
     |> patch_elements("#count", &render_count/1)}
  end

  @impl PhoenixDatastar
  def render(assigns) do
    ~H"""
    <div>
      Count: <span id="count">{@count}</span>
      <button data-on:click={event("increment")}>+</button>
    </div>
    """
  end

  defp render_count(assigns) do
    ~H|<span id="count">{@count}</span>|
  end
end
```

> **Note:** In previous versions you had to manually declare Datastar signals in your template
> with `data-signals={Jason.encode!(%{count: @count})}`. This is no longer needed — assigns
> set in `mount/3` are automatically injected as signals by the wrapper template.

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

```elixir
# Assign values
socket = assign(socket, :count, 0)
socket = assign(socket, count: 0, name: "test")

# Update with a function
socket = update(socket, :count, &(&1 + 1))

# Queue a DOM patch (sent via SSE)
socket = patch_elements(socket, "#selector", &render_fn/1)
socket = patch_elements(socket, "#selector", ~H|<span>html</span>|)
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
use MyAppWeb, :live_sse
# or: use PhoenixDatastar, :live
```

**Stateless views** handle events synchronously - state is restored from client signals on each request, and the response is returned immediately. No GenServer or SSE connection is maintained.

**Live views** maintain a GenServer and SSE connection. Use `:live` when you need:
- Real-time updates from the server (PubSub, timers)
- Persistent server-side state across interactions
- `handle_info/2` callbacks

## Links

- [Datastar](https://data-star.dev/) - The frontend library this integrates with
- [Phoenix LiveView](https://hexdocs.pm/phoenix_live_view/) - The inspiration for the callback design

## License

MIT License - see [LICENSE](LICENSE) for details.
