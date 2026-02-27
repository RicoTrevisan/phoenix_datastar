defmodule PhoenixDatastar.Actions do
  @moduledoc """
  Provides functions for generating Datastar action expressions.

  These functions generate Datastar-compatible action strings for use in
  `data-on:*` attributes in your templates.

  The generated expressions reference `$session_id` and `$event_path` Datastar
  signals, which are automatically initialized by `PhoenixDatastar.DefaultHTML`
  (or your custom `html_module`). This means `event/1,2` works in any component
  without needing to pass `session_id` or `event_path` through assigns.

  ## Requirements

  - A `<meta name="csrf-token" content="...">` tag must be present in your layout
    (Phoenix includes this by default)
  """

  use Phoenix.Component

  @doc """
  Generates a Datastar `@post` action expression for triggering server events.

  The generated expression references `$event_path` and `$session_id` signals,
  which Datastar resolves client-side. This means it works in any component
  regardless of nesting depth — no need to pass framework assigns through.

  ## Parameters

    * `event_name` - The event name to trigger on the server
    * `opts` - Optional additional options to pass in the request body (as a string)

  ## Examples

      # Simple event
      <button data-on:click={event("increment")}>+1</button>

      # Event with options
      <button data-on:click={event("toggle_code", "name: 'counter'")}>Toggle</button>

      # With signals
      <button data-on:click={event("update", "value: $count")}>Update</button>

  """
  @spec event(String.t(), String.t() | nil) :: String.t()
  def event(event_name, opts \\ nil) do
    build_event(event_name, opts)
  end

  @doc """
  Generates a Datastar `@post` action expression for in-session soft navigation.

  Posts to `/__datastar/nav` which is handled by `PhoenixDatastar.NavPlug`.
  The `$nav_token` signal is automatically included by Datastar in the request
  body (as part of the current signal payload) — no manual setup required.

  If the target route is a live view in the same `datastar_session`, navigation
  happens without a full page reload. Otherwise, falls back to `window.location`.

  ## Options

    * `:replace` - When `true`, uses `replaceState` instead of `pushState`.
      Defaults to `false`.

  ## Examples

      <button data-on:click={navigate("/dashboard/orgs")}>Go to orgs</button>
      <button data-on:click={navigate("/dashboard/orgs", replace: true)}>Replace</button>

  """
  @spec navigate(String.t(), keyword()) :: String.t()
  def navigate(path, opts \\ []) when is_binary(path) do
    mode = if Keyword.get(opts, :replace, false), do: "replace", else: "push"

    nav_url = "/__datastar/nav?_ds_to=#{URI.encode_www_form(path)}&_ds_mode=#{mode}"
    "if (evt.metaKey || evt.ctrlKey || evt.shiftKey || evt.altKey || evt.button !== 0) return; evt.preventDefault(); @post('#{nav_url}', {headers: {'x-csrf-token': document.querySelector('meta[name=csrf-token]').content}})"
  end

  attr(:navigate, :string, required: true)
  attr(:replace, :boolean, default: false)
  attr(:method, :atom, default: :soft, values: [:soft, :hard])
  attr(:rest, :global, include: ~w(class id target rel))
  slot(:inner_block, required: true)

  @doc """
  Link component that performs Datastar soft-navigation when possible.

  Renders an `<a>` tag with a normal `href` for accessibility, right-click context
  menus, and modified clicks (Ctrl/Cmd+click open in new tab). Unmodified left clicks
  are intercepted for soft navigation via `navigate/2`.

  ## Attributes

    * `:navigate` (required) — Target path.
    * `:replace` (boolean, default `false`) — Use `replaceState` instead of `pushState`.
    * `:method` (`:soft` or `:hard`, default `:soft`) — Set to `:hard` to force a full
      page navigation instead of soft navigation. Useful when navigation requires a full
      session refresh (e.g., switching workspaces).

  ## Examples

      <.ds_link navigate="/dashboard/orgs">Organizations</.ds_link>
      <.ds_link navigate="/dashboard/orgs" replace>Organizations</.ds_link>
      <.ds_link navigate="/other" method={:hard}>Full Reload</.ds_link>

  """
  def ds_link(assigns) do
    ~H"""
    <a href={@navigate} data-on:click={@method != :hard && navigate(@navigate, replace: @replace)} {@rest}>
      {render_slot(@inner_block)}
    </a>
    """
  end

  defp build_event(event_name, opts) do
    path = "$event_path+'/#{event_name}'"
    headers = "headers: {'x-csrf-token': document.querySelector('meta[name=csrf-token]').content}"
    session = "session_id: $session_id"

    if opts,
      do: "@post(#{path}, {#{session}, #{opts}, #{headers}})",
      else: "@post(#{path}, {#{session}, #{headers}})"
  end

end
