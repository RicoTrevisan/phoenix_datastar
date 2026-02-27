defmodule PhoenixDatastar.StreamTokenTest do
  use ExUnit.Case, async: true

  alias PhoenixDatastar.StreamToken

  import Phoenix.ConnTest
  import Plug.Conn

  defmodule TestEndpoint do
    def config(:secret_key_base), do: String.duplicate("a", 64)
  end

  defp build_test_conn do
    build_conn(:get, "/")
    |> put_private(:phoenix_endpoint, TestEndpoint)
  end

  describe "sign/2" do
    test "signs a payload and returns a string token" do
      conn = build_test_conn()
      payload = %{session_id: "abc123", path: "/counter"}

      token = StreamToken.sign(conn, payload)

      assert is_binary(token)
      assert String.length(token) > 0
    end

    test "signs an empty map payload" do
      conn = build_test_conn()

      token = StreamToken.sign(conn, %{})

      assert is_binary(token)
    end

    test "signs a payload with various data types" do
      conn = build_test_conn()
      payload = %{
        string: "hello",
        integer: 42,
        float: 3.14,
        boolean: true,
        list: [1, 2, 3],
        nested: %{key: "value"}
      }

      token = StreamToken.sign(conn, payload)

      assert is_binary(token)
    end

    test "raises when conn is missing phoenix_endpoint" do
      conn = build_conn(:get, "/")

      assert_raise RuntimeError, "Missing :phoenix_endpoint in conn.private", fn ->
        StreamToken.sign(conn, %{})
      end
    end

    test "produces different tokens for different payloads" do
      conn = build_test_conn()

      token1 = StreamToken.sign(conn, %{id: 1})
      token2 = StreamToken.sign(conn, %{id: 2})

      refute token1 == token2
    end

    test "produces different tokens on different calls (includes timestamp)" do
      conn = build_test_conn()
      payload = %{same: "data"}

      token1 = StreamToken.sign(conn, payload)
      # Small delay to ensure different timestamp
      :timer.sleep(1)
      token2 = StreamToken.sign(conn, payload)

      # Phoenix.Token includes signed_at timestamp, so tokens differ
      refute token1 == token2
    end
  end

  describe "verify/2 and verify/3" do
    test "verifies a valid token and returns the payload" do
      conn = build_test_conn()
      payload = %{session_id: "abc123", path: "/counter"}

      token = StreamToken.sign(conn, payload)
      result = StreamToken.verify(conn, token)

      assert {:ok, verified_payload} = result
      assert verified_payload == payload
    end

    test "verifies a token with empty map payload" do
      conn = build_test_conn()
      payload = %{}

      token = StreamToken.sign(conn, payload)
      result = StreamToken.verify(conn, token)

      assert {:ok, ^payload} = result
    end

    test "verifies a token with complex payload" do
      conn = build_test_conn()
      payload = %{
        string: "hello",
        integer: 42,
        list: [1, 2, 3],
        nested: %{key: "value"}
      }

      token = StreamToken.sign(conn, payload)
      result = StreamToken.verify(conn, token)

      assert {:ok, ^payload} = result
    end

    test "returns error for invalid token" do
      conn = build_test_conn()

      result = StreamToken.verify(conn, "invalid_token")

      assert {:error, :invalid} = result
    end

    test "returns error for empty string token" do
      conn = build_test_conn()

      result = StreamToken.verify(conn, "")

      assert {:error, :invalid} = result
    end

    test "returns error for tampered token" do
      conn = build_test_conn()
      payload = %{session_id: "abc123"}

      token = StreamToken.sign(conn, payload)
      # Tamper with the token
      tampered_token = token <> "x"

      result = StreamToken.verify(conn, tampered_token)

      assert {:error, :invalid} = result
    end

    test "raises when conn is missing phoenix_endpoint" do
      conn_with_endpoint = build_test_conn()
      conn_without_endpoint = build_conn(:get, "/")
      payload = %{test: true}

      token = StreamToken.sign(conn_with_endpoint, payload)

      assert_raise RuntimeError, "Missing :phoenix_endpoint in conn.private", fn ->
        StreamToken.verify(conn_without_endpoint, token)
      end
    end
  end

  describe "verify/3 with max_age option" do
    test "accepts custom max_age option" do
      conn = build_test_conn()
      payload = %{session_id: "abc123"}

      token = StreamToken.sign(conn, payload)
      result = StreamToken.verify(conn, token, max_age: 7200)

      assert {:ok, ^payload} = result
    end

    test "returns error when token is expired based on custom max_age" do
      conn = build_test_conn()
      payload = %{session_id: "abc123"}

      token = StreamToken.sign(conn, payload)
      # Use max_age of 0 to immediately expire the token
      :timer.sleep(1)
      result = StreamToken.verify(conn, token, max_age: 0)

      assert {:error, :expired} = result
    end

    test "uses application config for max_age when not provided" do
      # Save original config
      original = Application.get_env(:phoenix_datastar, :stream_token_max_age)

      try do
        Application.put_env(:phoenix_datastar, :stream_token_max_age, 0)

        conn = build_test_conn()
        payload = %{session_id: "abc123"}

        token = StreamToken.sign(conn, payload)
        :timer.sleep(1)
        result = StreamToken.verify(conn, token)

        assert {:error, :expired} = result
      after
        # Restore original config
        if original do
          Application.put_env(:phoenix_datastar, :stream_token_max_age, original)
        else
          Application.delete_env(:phoenix_datastar, :stream_token_max_age)
        end
      end
    end

    test "defaults to 3600 seconds when no config is set" do
      # This test verifies the default behavior - tokens should be valid
      # for up to 1 hour (3600 seconds) when no config is set
      conn = build_test_conn()
      payload = %{session_id: "abc123"}

      token = StreamToken.sign(conn, payload)
      # Token should be valid immediately
      result = StreamToken.verify(conn, token)

      assert {:ok, ^payload} = result
    end

    test "option max_age overrides application config" do
      original = Application.get_env(:phoenix_datastar, :stream_token_max_age)

      try do
        # Set app config to expire immediately
        Application.put_env(:phoenix_datastar, :stream_token_max_age, 0)

        conn = build_test_conn()
        payload = %{session_id: "abc123"}

        token = StreamToken.sign(conn, payload)
        # But override with a long max_age
        result = StreamToken.verify(conn, token, max_age: 3600)

        # Should succeed because option overrides config
        assert {:ok, ^payload} = result
      after
        if original do
          Application.put_env(:phoenix_datastar, :stream_token_max_age, original)
        else
          Application.delete_env(:phoenix_datastar, :stream_token_max_age)
        end
      end
    end
  end

  describe "cross-endpoint verification" do
    defmodule OtherEndpoint do
      def config(:secret_key_base), do: String.duplicate("b", 64)
    end

    test "returns error when verified with different endpoint secret" do
      conn1 = build_test_conn()
      conn2 = build_conn(:get, "/") |> put_private(:phoenix_endpoint, OtherEndpoint)
      payload = %{session_id: "abc123"}

      token = StreamToken.sign(conn1, payload)
      result = StreamToken.verify(conn2, token)

      assert {:error, :invalid} = result
    end
  end

  describe "guard clauses" do
    test "sign/2 requires payload to be a map" do
      conn = build_test_conn()

      # These should raise FunctionClauseError due to guard
      assert_raise FunctionClauseError, fn ->
        StreamToken.sign(conn, "not a map")
      end

      assert_raise FunctionClauseError, fn ->
        StreamToken.sign(conn, [key: "value"])
      end

      assert_raise FunctionClauseError, fn ->
        StreamToken.sign(conn, 123)
      end
    end

    test "verify/2 requires token to be a binary" do
      conn = build_test_conn()

      assert_raise FunctionClauseError, fn ->
        StreamToken.verify(conn, 123)
      end

      assert_raise FunctionClauseError, fn ->
        StreamToken.verify(conn, nil)
      end

      assert_raise FunctionClauseError, fn ->
        StreamToken.verify(conn, %{})
      end
    end
  end
end
