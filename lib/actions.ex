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
  def event(event_name, opts \\ nil) do
    build_event(event_name, opts)
  end

  @doc false
  def build_event(event_name, opts) do
    path = "$event_path+'/#{event_name}'"
    headers = "headers: {'x-csrf-token': document.querySelector('meta[name=csrf-token]').content}"
    session = "session_id: $session_id"

    if opts,
      do: "@post(#{path}, {#{session}, #{opts}, #{headers}})",
      else: "@post(#{path}, {#{session}, #{headers}})"
  end

  @doc false
  @deprecated "Use build_event/2 instead — session_id and event_path are now read from Datastar signals"
  def build_event(event_name, _session_id, _event_path, opts) do
    build_event(event_name, opts)
  end
end
