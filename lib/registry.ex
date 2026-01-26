defmodule PhoenixDatastar.Registry do
  @moduledoc """
  Dynamic process registry for PhoenixDatastar GenServers.

  Each live SSE session gets a GenServer process. This module provides helpers
  for naming and looking up these processes via Elixir's Registry, keyed by session_id.

  ## Setup

  The Registry must be started in your application supervisor:

      {Registry, keys: :unique, name: PhoenixDatastar.Registry}
  """

  @doc """
  Generate a registry "via tuple" for a given session_id.

  Returns a tuple suitable for GenServer's `:name` option to dynamically
  register and lookup processes.

  ## Examples

      iex> PhoenixDatastar.Registry.via("session-abc123")
      {:via, Registry, {PhoenixDatastar.Registry, "session-abc123"}}
  """
  @spec via(String.t()) :: {:via, Registry, {module(), String.t()}}
  def via(session_id) when is_binary(session_id) do
    {:via, Registry, {__MODULE__, session_id}}
  end
end
