defmodule PhoenixDatastar.Actions do
  @moduledoc """
  Provides macros for generating Datastar action expressions.

  These macros generate Datastar-compatible action strings for use in
  `data-on:*` attributes in your templates.

  ## Requirements

  - `assigns.base_path` must be set in your template context
  - `$_csrf_token` signal must be available (typically set via `data-signals:_csrf_token`)
  """

  @doc """
  Generates a Datastar `@post` action expression for triggering server events.

  The generated action will POST to `{base_path}/event/{event}` with CSRF token headers.

  ## Parameters

    * `event` - The event name to trigger on the server
    * `opts` - Optional additional options to pass in the request body (as a string)

  ## Examples

      # Simple event
      <button data-on:click={post("increment")}>+1</button>

      # Event with options
      <button data-on:click={post("toggle_code", "name: 'counter'")}>Toggle</button>

      # With signals
      <button data-on:click={post("update", "value: $count")}>Update</button>

  """
  defmacro post(event, opts \\ nil) do
    quote do
      PhoenixDatastar.Actions.build_post(
        var!(assigns).base_path,
        unquote(event),
        unquote(opts)
      )
    end
  end

  @doc """
  Generates a Datastar `@get` action expression for fetching data from the server.

  The generated action will GET from `{base_path}/event/{event}` with CSRF token headers.

  ## Parameters

    * `event` - The event name to trigger on the server
    * `opts` - Optional additional options to pass in the request (as a string)

  ## Examples

      # Simple fetch
      <button data-on:click={get("refresh")}>Refresh</button>

      # Fetch with options
      <button data-on:click={get("load_more", "page: $currentPage")}>Load More</button>

      # On load trigger
      <div data-on:load={get("init")}>Loading...</div>

  """
  defmacro get(event, opts \\ nil) do
    quote do
      PhoenixDatastar.Actions.build_get(
        var!(assigns).base_path,
        unquote(event),
        unquote(opts)
      )
    end
  end

  @doc false
  def build_post(base_path, event, opts) do
    path = "#{base_path}/event/#{event}" |> String.replace("//", "/")
    headers = "headers: {'x-csrf-token': $_csrf_token}"

    if opts,
      do: "@post('#{path}', {#{opts}, #{headers}})",
      else: "@post('#{path}', {#{headers}})"
  end

  @doc false
  def build_get(base_path, event, opts) do
    path = "#{base_path}/event/#{event}" |> String.replace("//", "/")
    headers = "headers: {'x-csrf-token': $_csrf_token}"

    if opts,
      do: "@get('#{path}', {#{opts}, #{headers}})",
      else: "@get('#{path}', {#{headers}})"
  end
end
