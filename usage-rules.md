# PhoenixDatastar Usage Rules

## What This Is

PhoenixDatastar provides a LiveView-like developer experience using **SSE (Server-Sent Events) + Datastar Signals** instead of WebSockets. It is NOT LiveView — it uses a fundamentally different transport and reactivity model based on the [Datastar](https://data-star.dev/) frontend library.

## Two Modes

- **Stateless** (`use PhoenixDatastar`) — No persistent connection. State lives on the client as signals. Each event POST restores state from signals, runs `handle_event/3`, and returns SSE-formatted patches in the response body.
- **Live** (`use PhoenixDatastar, :live`) — Persistent SSE connection with a GenServer. Supports `handle_info/2` for PubSub, timers, and server-initiated pushes.

Choose stateless unless you need server-push (PubSub, timers, periodic updates).

## Assigns vs Signals

PhoenixDatastar separates server-side state from client-side reactive state:

- **Assigns** (`assign/2,3`, `update/3`) are server-side state, never sent to the client. They are available in templates as `@key`. Use them for structs, DB records, or any data the server needs to remember or render HTML with.

- **Signals** (`put_signal/2,3`, `update_signal/3`) are Datastar reactive state sent to the client via SSE. They must be JSON-serializable. The client accesses them via Datastar expressions like `$count`. Signals are **not** available as `@key` in templates — Datastar handles their rendering client-side.

Signals set via `put_signal` in `mount/3` are automatically initialized as Datastar signals on the client via `@initial_signals` in `DefaultHTML`. **Do NOT manually add `data-signals` for signals set in mount** — they are injected automatically.

Client signals arrive as the `payload` argument in `handle_event/3`. They are untrusted input — read, validate, and explicitly `put_signal` what you want to send back.

## Module Structure

```elixir
defmodule MyAppWeb.CounterStar do
  use MyAppWeb, :live_datastar  # or :datastar for stateless

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
      <span data-text="$count"></span>
      <button data-on:click={event("increment")}>+</button>
    </div>
    """
  end
end
```

### Server-Rendered Patches with Assigns

For complex rendering, use assigns for server-side state and `patch_elements` to push HTML updates:

```elixir
defmodule MyAppWeb.ItemsStar do
  use MyAppWeb, :live_datastar

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
    ~H|<ul id="items"><li :for={item <- @items}>{item}</li></ul>|
  end
end
```

> **Tip:** You can combine both patterns — use `put_signal` for simple reactive values
> (toggles, counters, form inputs) and `assign` + `patch_elements` for complex
> server-rendered sections.

### Callbacks

| Callback | Required | Modes | Returns |
|---|---|---|---|
| `mount/3` | Yes | Both | `{:ok, socket}` or `{:ok, socket, opts}` |
| `render/1` | Yes | Both | `~H` template |
| `handle_event/3` | No (has default) | Both | `{:noreply, socket}` or `{:stop, socket}` |
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
- `GET /counter` — initial page load (mount + render via `PhoenixDatastar.PageController`)
- `POST /counter/_event/:event` — event handler (via `PhoenixDatastar.Plug`)

For live views, a **global** SSE stream endpoint must also be added (see Session Navigation below).

### Session Navigation

`datastar_session/3` groups routes under shared session navigation settings. This enables soft navigation (SPA-like page transitions) between live views without full page reloads.

```elixir
import PhoenixDatastar.Router

# Global Datastar endpoints (stream + nav)
scope "/__datastar" do
  get "/stream", PhoenixDatastar.StreamPlug, :stream
  post "/nav", PhoenixDatastar.NavPlug, :navigate
end

scope "/", MyAppWeb do
  pipe_through [:browser, :require_user]

  datastar_session :dashboard,
    root_selector: "#dashboard-root" do
    datastar "/dashboard", DashboardStar
    datastar "/dashboard/orgs", DashboardOrgsStar
  end
end
```

#### `datastar_session/3` Options

- `:root_selector` — CSS selector for the container element patched during soft navigation. Defaults to `"#app"`.

#### How soft navigation works

1. Client clicks a `<.ds_link>` or calls `navigate("/path")`.
2. `POST /__datastar/nav` is sent with the signed `nav_token` (sent automatically as a Datastar signal).
3. `NavPlug` verifies the token, matches the target route via `RouteRegistry`, and checks the target is a live view in the same `datastar_session`.
4. If valid: `Server.navigate/5` swaps the view in the existing GenServer, pushes new HTML + signals + `pushState` through the SSE stream. A fresh `nav_token` is issued.
5. If invalid (different session, stateless target, or unknown route): falls back to a full page reload via `window.location`.

**Soft navigation only works between live views** (`use PhoenixDatastar, :live`) **within the same `datastar_session`**. Stateless views always trigger a full page reload.

#### Key modules

- **`PhoenixDatastar.StreamPlug`** — Handles `GET /__datastar/stream?token=...`. Verifies the stream token, subscribes to the GenServer, and enters the SSE loop.
- **`PhoenixDatastar.NavPlug`** — Handles `POST /__datastar/nav`. Verifies the nav token, matches the target route, and either performs soft navigation or falls back to a full reload.
- **`PhoenixDatastar.StreamToken`** — Signs and verifies Phoenix tokens for stream/nav authorization. Default max age: 3600 seconds, configurable via `config :phoenix_datastar, :stream_token_max_age`.
- **`PhoenixDatastar.RouteRegistry`** — Runtime route lookup for session-aware navigation. Uses route metadata compiled by the `datastar/3` macro.

## Socket API

The socket struct (`PhoenixDatastar.Socket`) is the primary state container, similar to `Phoenix.LiveView.Socket`.

### Assigns (server-side state)

```elixir
assign(socket, :key, value)
assign(socket, key1: val1, key2: val2)
update(socket, :key, &(&1 + 1))
```

### Signals (client-side Datastar state)

```elixir
put_signal(socket, :count, 0)
put_signal(socket, count: 0, name: "test")
update_signal(socket, :count, &(&1 + 1))
```

### DOM Patching

`patch_elements/3` queues HTML patches sent via SSE. Always pair a CSS selector with a matching element:

```elixir
# With a render function (recommended — uses current assigns)
socket |> patch_elements("#count", &render_count/1)

# With raw HTML
socket |> patch_elements("#count", ~H|<span id="count">{@count}</span>|)
```

The selector targets which element to replace. The rendered HTML **must include the element itself** (outer replace by default). The render function receives `socket.assigns` (server-side state only, not signals).

### Scripts and Navigation

```elixir
socket |> execute_script("alert('hi')")
socket |> redirect("/dashboard")
socket |> console_log("debug info", level: :warn)
```

## Actions (Template Helpers)

Import `PhoenixDatastar.Actions` (auto-imported by `:live_datastar` / `:datastar` helpers).

### `event/1,2`

Generates a Datastar `@post(...)` expression for triggering server events:

```elixir
<button data-on:click={event("increment")}>+</button>
<button data-on:click={event("update", "value: $count")}>Update</button>
```

Uses `$session_id` and `$event_path` Datastar signals (initialized automatically by `DefaultHTML`), so it works in any component without passing framework assigns through. A `<meta name="csrf-token">` tag must exist in the layout (Phoenix default).

### `navigate/1,2`

Generates a Datastar `@post(...)` expression for in-session soft navigation:

```elixir
<button data-on:click={navigate("/dashboard/orgs")}>Go to orgs</button>
<button data-on:click={navigate("/dashboard/orgs", replace: true)}>Replace</button>
```

The generated expression posts to `/__datastar/nav` with the target path. The `$nav_token` signal is automatically sent by Datastar as part of the signal payload — no manual setup required.

### `<.ds_link>`

Link component that performs Datastar soft navigation when possible, with a normal `href` fallback for accessibility, right-click, and modified clicks (Ctrl/Cmd+click):

```elixir
<.ds_link navigate="/dashboard/orgs">Organizations</.ds_link>
<.ds_link navigate="/dashboard/orgs" replace>Organizations</.ds_link>
<.ds_link navigate="/other" method={:hard}>Full Reload</.ds_link>
```

Attributes:
- `:navigate` (required) — Target path.
- `:replace` (boolean, default `false`) — Use `replaceState` instead of `pushState`.
- `:method` (`:soft` or `:hard`, default `:soft`) — Set to `:hard` to force a full page navigation instead of soft navigation.

## Lifecycle

1. **GET /path** — `mount/3` → `render/1` → full HTML response wrapped by `DefaultHTML` (or custom `html_module`)
2. **GET /__datastar/stream?token=...** (live only) — opens persistent SSE connection via `StreamPlug`, subscribes to GenServer updates
3. **POST /path/_event/:event** — triggers `handle_event/3`
   - Live: dispatches to GenServer, updates pushed via SSE stream
   - Stateless: restores state from client signals, returns SSE patches in response body
4. **POST /__datastar/nav** (session nav) — `NavPlug` verifies token, performs soft navigation or falls back to full reload

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
- **Soft navigation is live-to-live only.** Navigation between views in the same `datastar_session` only works when both source and target are live views. Stateless views always trigger a full page reload.

## Configuration

```elixir
# config/config.exs
config :phoenix_datastar, :html_module, MyAppWeb.DatastarHTML  # optional custom wrapper
config :phoenix_datastar, :stream_token_max_age, 3600          # stream/nav token expiry in seconds (default: 1 hour)

# config/dev.exs
config :phoenix_datastar, :strip_debug_annotations, true  # strip LiveView debug comments from patches
```

## Installation

Prefer `mix igniter.install phoenix_datastar` — it handles supervision tree, router, web module, and layout setup automatically.

For manual installation, add `{:phoenix_datastar, "~> 0.1"}` to deps and follow the README setup steps:
1. Add Datastar JS to layout `<head>`
2. Add `{Registry, keys: :unique, name: PhoenixDatastar.Registry}` to supervision tree
3. Import `PhoenixDatastar.Router` in your router
4. Add global Datastar endpoints (`StreamPlug`, `NavPlug`) for live session support
5. Add `:live_datastar` and `:datastar` helpers to your `_web.ex`
