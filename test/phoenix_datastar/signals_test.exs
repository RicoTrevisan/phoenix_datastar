defmodule PhoenixDatastar.SignalsTest do
  use ExUnit.Case

  alias PhoenixDatastar.Signals

  describe "read/1" do
    test "reads signals from GET request query params" do
      conn = %Plug.Conn{
        method: "GET",
        query_params: %{"datastar" => ~s({"count": 10, "name": "test"})}
      }

      signals = Signals.read(conn)

      assert signals == %{"count" => 10, "name" => "test"}
    end

    test "returns empty map when no signals in GET request" do
      conn = %Plug.Conn{method: "GET", query_params: %{}}

      signals = Signals.read(conn)

      assert signals == %{}
    end

    test "reads signals from POST request body params" do
      conn = %Plug.Conn{
        method: "POST",
        body_params: %{"count" => 5, "action" => "increment"}
      }

      signals = Signals.read(conn)

      assert signals == %{"count" => 5, "action" => "increment"}
    end

    test "handles invalid JSON gracefully" do
      conn = %Plug.Conn{
        method: "GET",
        query_params: %{"datastar" => "not valid json"}
      }

      signals = Signals.read(conn)

      assert signals == %{}
    end
  end

  describe "read_as/2" do
    defmodule TestSignals do
      defstruct [:count, :name]
    end

    test "converts signals to a struct" do
      conn = %Plug.Conn{
        method: "GET",
        query_params: %{"datastar" => ~s({"count": 10, "name": "test"})}
      }

      {:ok, signals} = Signals.read_as(conn, TestSignals)

      assert signals.count == 10
      assert signals.name == "test"
    end
  end
end
