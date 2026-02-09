# PhoenixDatastar Usage Rules

## What This Is

PhoenixDatastar provides a LiveView-like developer experience using **SSE (Server-Sent Events) + Datastar Signals** instead of WebSockets. It is NOT LiveView — it uses a fundamentally different transport and reactivity model based on the [Datastar](https://data-star.dev/) frontend library.

## Two Modes

- **Stateless** (`use PhoenixDatastar`) — No persistent connection. State lives on the client as signals. Each event POST restores state from signals, runs `handle_event/3`, and returns SSE-formatted patches in the response body.
- **Live** (`use PhoenixDatastar, :live`) — Persistent SSE connection with a GenServer. Supports `handle_info/2` for PubSub, timers, and server-initiated pushes.

Choose stateless unless you need server-push (PubSub, timers, periodic updates).

## Module Structure

```elixir
defmodule MyAppWeb.CounterStar do
  use MyAppWeb, :live_sse  # or :datastar for stateless

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
      <span id="count">{@count}</span>
      <button data-on:click={event("increment")}>+</button>
    </div>
    """
  end

  defp render_count(assigns), do: ~H|<span id="count">{@count}</span>|
end
```

### Callbacks

| Callback | Required | Modes | Returns |
|---|---|---|---|
| `mount/3` | Yes | Both | `{:ok, socket}` |
| `render/1` | Yes | Both | `~H` template |
| `handle_event/3` | Yes | Both | `{:noreply, socket}` or `{:stop, socket}` |
| `handle_info/2` | No | Live only | `{:noreply, socket}` |
| `terminate/1` | No | Live only | `:ok` |

Always annotate callbacks with `@impl PhoenixDatastar`.

## Router

```elixir
import PhoenixDatastar.Router

scope "/", MyAppWeb do
  pipe_through :browser
  datastar "/counter", CounterStar
  datastar "/custom", CustomStar, html_module: MyAppWeb.DatastarHTML
end
```

`datastar/3` generates:
- `GET /counter` — initial page load (mount + render)
- `POST /counter/_event/:event` — event handler
- `GET /counter/stream` — SSE stream (live views only)

## Socket API

The socket struct (`PhoenixDatastar.Socket`) is the primary state container, similar to `Phoenix.LiveView.Socket`.

### Assigns

```elixir
assign(socket, :key, value)
assign(socket, key1: val1, key2: val2)
update(socket, :key, &(&1 + 1))
```

### DOM Patching

`patch_elements/3` queues HTML patches sent via SSE. Always pair a CSS selector with a matching element:

```elixir
# With a render function (recommended — uses current assigns)
socket |> patch_elements("#count", &render_count/1)

# With raw HTML
socket |> patch_elements("#count", ~H|<span id="count">{@count}</span>|)
```

The selector targets which element to replace. The rendered HTML **must include the element itself** (outer replace by default).

### Scripts

```elixir
socket |> execute_script("alert('hi')")
socket |> redirect("/dashboard")
socket |> console_log("debug info", level: :warn)
```

## Actions (Template Helpers)

Import `PhoenixDatastar.Actions` (auto-imported by `:live_sse` / `:datastar` helpers).

### `event/1,2`

Generates a Datastar `@post(...)` expression for triggering server events:

```elixir
<button data-on:click={event("increment")}>+</button>
<button data-on:click={event("update", "value: $count")}>Update</button>
```

Requires `assigns.session_id` and `assigns.event_path` (both set automatically). A `<meta name="csrf-token">` tag must exist in the layout (Phoenix default).

## Signals

- Assigns set in `mount/3` are **automatically initialized as Datastar signals** on the client. Do NOT manually add `data-signals` for mount assigns.
- Internal assigns (`:session_id`, `:base_path`, `:stream_path`, `:event_path`, `:flash`) are filtered out — they never become client signals.
- Read signals from a connection: `PhoenixDatastar.Signals.read(conn)` returns a map.
- Patch signals on an SSE stream: `PhoenixDatastar.Signals.patch(sse, %{key: value})`.

## Lifecycle

1. **GET /path** — `mount/3` → `render/1` → full HTML response wrapped by `DefaultHTML` (or custom `html_module`)
2. **GET /path/stream** (live only) — opens persistent SSE connection, subscribes to GenServer updates
3. **POST /path/_event/:event** — triggers `handle_event/3`
   - Live: dispatches to GenServer, updates pushed via SSE stream
   - Stateless: restores state from client signals, returns SSE patches in response body

## Common Patterns

### Updating multiple elements in one event

```elixir
def handle_event("submit", payload, socket) do
  {:noreply,
   socket
   |> assign(:name, payload["name"])
   |> patch_elements("#greeting", &render_greeting/1)
   |> patch_elements("#status", &render_status/1)}
end
```

### PubSub with live views

```elixir
def mount(_params, _session, socket) do
  Phoenix.PubSub.subscribe(MyApp.PubSub, "updates")
  {:ok, assign(socket, data: nil)}
end

def handle_info({:new_data, data}, socket) do
  {:noreply,
   socket
   |> assign(:data, data)
   |> patch_elements("#data", &render_data/1)}
end
```

### Referencing signal values in Datastar expressions

Use `$signal_name` in Datastar attribute expressions:

```elixir
<span data-text="$count"></span>
<div data-show="$visible"></div>
<input data-bind:value="$name" />
```

## Gotchas

- **Always include the target element in patch HTML.** `patch_elements("#count", ...)` does an outer replace — the rendered fragment must include the `<span id="count">...</span>` wrapper.
- **Stateless views have no `handle_info/2`.** State is ephemeral and reconstructed from client signals on each POST.
- **`strip_debug_annotations` in dev.** Set `config :phoenix_datastar, :strip_debug_annotations, true` in `dev.exs` to remove LiveView debug comments from SSE patches.
- **Don't confuse with LiveView.** There are no LiveView processes, channels, or sockets. PhoenixDatastar uses plain HTTP + SSE.
- **The `DefaultHTML` wrapper is automatic.** It injects `data-signals` and `data-init__once` for SSE. Only create a custom `html_module` if you need to change the wrapper markup.

## Configuration

```elixir
# config/config.exs
config :phoenix_datastar, :html_module, MyAppWeb.DatastarHTML  # optional custom wrapper

# config/dev.exs
config :phoenix_datastar, :strip_debug_annotations, true  # strip LiveView debug comments from patches
```

## Installation

Prefer `mix igniter.install phoenix_datastar` — it handles supervision tree, router, web module, and layout setup automatically.

For manual installation, add `{:phoenix_datastar, "~> 0.1"}` to deps and follow the README setup steps:
1. Add Datastar JS to layout `<head>`
2. Add `{Registry, keys: :unique, name: PhoenixDatastar.Registry}` to supervision tree
3. Import `PhoenixDatastar.Router` in your router
4. Add `:live_sse` and `:datastar` helpers to your `_web.ex`
