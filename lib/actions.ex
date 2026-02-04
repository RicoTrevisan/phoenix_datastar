defmodule PhoenixDatastar.Actions do
  @moduledoc """
  Provides macros for generating Datastar action expressions.

  These macros generate Datastar-compatible action strings for use in
  `data-on:*` attributes in your templates.

  ## Requirements

  - `assigns.session_id` must be set in your template context (automatically set by PhoenixDatastar)
  - `assigns.event_path` must be set (automatically set by PhoenixDatastar)
  - A `<meta name="csrf-token" content="...">` tag must be present in your layout (Phoenix includes this by default)
  """

  @doc """
  Generates a Datastar `@post` action expression for triggering server events.

  The generated action will POST to `{event_path}/{event}` with the session ID
  and CSRF token.

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
  defmacro event(event_name, opts \\ nil) do
    quote do
      PhoenixDatastar.Actions.build_event(
        unquote(event_name),
        var!(assigns).session_id,
        var!(assigns).event_path,
        unquote(opts)
      )
    end
  end

  @doc false
  def build_event(event_name, session_id, event_path, opts) do
    path = "#{event_path}/#{event_name}"
    headers = "headers: {'x-csrf-token': document.querySelector('meta[name=csrf-token]').content}"
    session = "session_id: '#{session_id}'"

    if opts,
      do: "@post('#{path}', {#{session}, #{opts}, #{headers}})",
      else: "@post('#{path}', {#{session}, #{headers}})"
  end
end
