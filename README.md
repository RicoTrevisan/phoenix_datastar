> [!WARNING]
> This is still in alpha, I'm figuring out the right apis.

# PhoenixDatastar

**A LiveView-like experience for Phoenix using Datastar's SSE + Signals architecture.**

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
- Add `import PhoenixDatastar.Router` to your router
- Add `"sse"` to the browser pipeline's `:accepts` plug
- Add `def live_sse` and `def datastar` to your web module
- Add the Datastar JavaScript to your root layout's `<head>`
- Add `data-signals` and `data-init__once` attributes to `<body>` in your root layout

You'll then just need to add routes (the installer will show you instructions).

### Manual Installation

Add `phoenix_datastar` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:phoenix_datastar, "~> 0.1.3"}
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

#### 3. Add signal attributes to your root layout

In your `root.html.heex`, add the Datastar attributes to the `<body>` tag:

```html
<body
  data-signals={@datastar_session_id && Jason.encode!(%{session_id: @datastar_session_id})}
  data-init__once={@datastar_stream_path && "@get('#{@datastar_stream_path}', {openWhenHidden: true})"}
>
```

These attributes are conditionally rendered — on non-Datastar pages they are omitted since the assigns are not set.

#### 4. Import the router macro

In your router:

```elixir
import PhoenixDatastar.Router

scope "/", MyAppWeb do
  pipe_through :browser

  datastar "/counter", CounterStar
end
```

#### 5. Create `:live_sse` and `:datastar` in your `_web.ex`

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

#### 6. Strip debug annotations in dev (optional)

In your `config/dev.exs`, enable stripping of LiveView debug annotations from SSE patches:

```elixir
config :phoenix_datastar, :strip_debug_annotations, true
```

This removes `<!-- @caller ... -->` comments and `data-phx-loc` attributes from SSE patches. The initial page load keeps annotations intact for debugging.


## Usage

### Basic Example

```elixir
defmodule MyAppWeb.CounterStar do
  use MyAppWeb, :live_sse
  # if not present in `my_app_web.ex` file use
  # `use PhoenixDatastar, :live`

  @impl PhoenixDatastar
  def mount(_params, _session, socket) do
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
