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
- Configure the HTML module
- Enable stripping of debug annotations in dev
- Create the DatastarHTML module

You'll then just need to manually add the Datastar JavaScript to your layout and import the router macro (the installer will show you instructions).

### Manual Installation

Add `phoenix_datastar` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:phoenix_datastar, "~> 0.1.1"}
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

#### 3. Configure the HTML module
Create a module that renders the mount template. This wraps the body with a signal and a call to get the sse stream started.

In your `config/config.exs`:

```elixir
config :phoenix_datastar, :html_module, MyAppWeb.DatastarHTML
```

```elixir
defmodule MyAppWeb.DatastarHTML do
  use Phoenix.Component

  def mount(assigns) do
    ~H"""
      <div 
        id={"ds-live-#{@session_id}"} 
        data-signals={"{session_id: '#{@session_id}'}"}
        data-init__once={@stream_path && "@get('#{@stream_path}', {openWhenHidden: true})"}
      >
        {@inner_html}
      </div>
    """
  end
end
```

#### 4. Import the router macro 

In your router:

```elixir
import PhoenixDatastar.Router

scope "/", MyAppWeb do
  pipe_through :browser

  datastar "/counter", CounterStar
end
```

#### 5. Create `:live_sse` in your `_web.ex`

```ex
defmodule MyAppWeb do
#... existing calls

  def live_sse do
    quote do
      use PhoenixDatastar, :live

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
      <button data-on:click={post("increment")}>+</button>
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
2. **SSE Connection**: `GET /counter/stream` opens a persistent connection, starts a GenServer
3. **User Interactions**: `POST /counter/event/:event` triggers `handle_event/3`, updates pushed via SSE

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

- `assigns.base_path` must be set in your template context (automatically set by PhoenixDatastar)
- `$_csrf_token` signal must be available (typically set via `data-signals:_csrf_token`)

### `post/2`

Generates a Datastar `@post` action for triggering server events.

```elixir
# Simple event
<button data-on:click={post("increment")}>+1</button>

# Event with options
<button data-on:click={post("toggle_code", "name: 'counter'")}>Toggle</button>

# With signals
<button data-on:click={post("update", "value: $count")}>Update</button>
```

### `get/2`

Generates a Datastar `@get` action for fetching data from the server.

```elixir
# Simple fetch
<button data-on:click={get("refresh")}>Refresh</button>

# Fetch with options
<button data-on:click={get("load_more", "page: $currentPage")}>Load More</button>

# On load trigger
<div data-on:load={get("init")}>Loading...</div>
```

## Stateless vs Live Views

```elixir
# Stateless view - no persistent connection
use PhoenixDatastar

# Live view - persistent SSE connection with GenServer state
use PhoenixDatastar, :live
```

Use `:live` when you need:
- Real-time updates from the server (PubSub, timers)
- Persistent state across interactions
- `handle_info/2` callbacks

## Links

- [Datastar](https://data-star.dev/) - The frontend library this integrates with
- [Phoenix LiveView](https://hexdocs.pm/phoenix_live_view/) - The inspiration for the callback design

## License

MIT License - see [LICENSE](LICENSE) for details.
