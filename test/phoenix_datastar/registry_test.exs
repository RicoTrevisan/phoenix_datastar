defmodule PhoenixDatastar.RegistryTest do
  use ExUnit.Case, async: true

  alias PhoenixDatastar.Registry

  describe "via/1" do
    test "returns a via tuple for a valid session_id" do
      session_id = "session-abc123"
      result = Registry.via(session_id)

      assert {:via, Elixir.Registry, {PhoenixDatastar.Registry, ^session_id}} = result
    end

    test "returns correct structure with UUID-like session_id" do
      session_id = "550e8400-e29b-41d4-a716-446655440000"
      result = Registry.via(session_id)

      assert {:via, Elixir.Registry, {PhoenixDatastar.Registry, ^session_id}} = result
    end

    test "handles empty string session_id" do
      # Empty strings are valid binaries, so this should work
      result = Registry.via("")

      assert {:via, Elixir.Registry, {PhoenixDatastar.Registry, ""}} = result
    end

    test "handles session_id with special characters" do
      session_id = "session/with:special-chars_123"
      result = Registry.via(session_id)

      assert {:via, Elixir.Registry, {PhoenixDatastar.Registry, ^session_id}} = result
    end

    test "raises FunctionClauseError for atom input" do
      assert_raise FunctionClauseError, fn ->
        Registry.via(:session_atom)
      end
    end

    test "raises FunctionClauseError for integer input" do
      assert_raise FunctionClauseError, fn ->
        Registry.via(12345)
      end
    end

    test "raises FunctionClauseError for nil input" do
      assert_raise FunctionClauseError, fn ->
        Registry.via(nil)
      end
    end

    test "raises FunctionClauseError for list input" do
      assert_raise FunctionClauseError, fn ->
        Registry.via(["session", "123"])
      end
    end

    test "raises FunctionClauseError for map input" do
      assert_raise FunctionClauseError, fn ->
        Registry.via(%{session_id: "abc123"})
      end
    end

    test "raises FunctionClauseError for charlist input" do
      # Charlists are lists, not binaries
      assert_raise FunctionClauseError, fn ->
        Registry.via(~c"session-123")
      end
    end

    test "via tuple can be used with Registry.whereis/1" do
      session_id = "test-session-for-lookup"
      via_tuple = Registry.via(session_id)

      # Start the registry if not started (for integration testing)
      start_supervised!({Elixir.Registry, keys: :unique, name: PhoenixDatastar.Registry})

      # Initially, no process should be registered
      assert Elixir.Registry.lookup(PhoenixDatastar.Registry, session_id) == []

      # Register a dummy process
      {:ok, agent} = Agent.start_link(fn -> :ok end, name: via_tuple)

      # Now we should find the process
      [{pid, _}] = Elixir.Registry.lookup(PhoenixDatastar.Registry, session_id)
      assert pid == agent

      # Clean up
      Agent.stop(agent)
    end
  end
end
