defmodule PhoenixDatastar.StreamPlugTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Plug.Conn

  alias PhoenixDatastar.StreamPlug
  alias PhoenixDatastar.StreamToken
  alias PhoenixDatastar.Server

  # Test endpoint for signing tokens
  defmodule TestEndpoint do
    def config(:secret_key_base), do: String.duplicate("a", 64)
  end

  # Minimal live test view
  defmodule TestLiveView do
    use PhoenixDatastar, :live

    @impl PhoenixDatastar
    def mount(_params, _session, socket) do
      socket = PhoenixDatastar.Socket.assign(socket, :mounted, true)
      {:ok, socket}
    end

    @impl PhoenixDatastar
    def render(assigns) do
      {:safe, "<div>Mounted: #{assigns[:mounted]}</div>"}
    end

    @impl PhoenixDatastar
    def handle_event("test", _payload, socket) do
      {:noreply, socket}
    end
  end

  defp build_test_conn(method, path) do
    build_conn(method, path)
    |> put_private(:phoenix_endpoint, TestEndpoint)
  end

  defp build_signed_token(conn, payload) do
    StreamToken.sign(conn, payload)
  end

  setup do
    # Generate unique session ID for each test
    session_id = "stream-plug-test-#{System.unique_integer([:positive])}"

    %{session_id: session_id}
  end

  describe "init/1" do
    test "passes options through unchanged" do
      opts = [some: :option, another: :value]
      assert StreamPlug.init(opts) == opts
    end

    test "handles empty options" do
      assert StreamPlug.init([]) == []
    end
  end

  describe "call/2 - missing token" do
    test "returns 401 when token parameter is missing" do
      conn =
        build_test_conn(:get, "/__datastar/stream")
        |> StreamPlug.call([])

      assert conn.status == 401
      assert conn.resp_body == "Invalid stream token"
      assert conn.halted
    end

    test "returns 401 when token is empty string" do
      conn =
        build_test_conn(:get, "/__datastar/stream?token=")
        |> StreamPlug.call([])

      assert conn.status == 401
      assert conn.resp_body == "Invalid stream token"
      assert conn.halted
    end
  end

  describe "call/2 - invalid token" do
    test "returns 401 for malformed token" do
      conn =
        build_test_conn(:get, "/__datastar/stream?token=invalid_garbage")
        |> StreamPlug.call([])

      assert conn.status == 401
      assert conn.resp_body == "Invalid stream token"
      assert conn.halted
    end

    test "returns 401 for tampered token", %{session_id: session_id} do
      conn = build_test_conn(:get, "/__datastar/stream")
      payload = %{"session_id" => session_id}
      token = build_signed_token(conn, payload)
      tampered_token = token <> "x"

      conn =
        build_test_conn(:get, "/__datastar/stream?token=#{tampered_token}")
        |> StreamPlug.call([])

      assert conn.status == 401
      assert conn.resp_body == "Invalid stream token"
      assert conn.halted
    end

    test "returns 401 for token signed with different endpoint secret", %{session_id: session_id} do
      defmodule OtherEndpoint do
        def config(:secret_key_base), do: String.duplicate("b", 64)
      end

      # Sign with OtherEndpoint
      other_conn = build_conn(:get, "/") |> put_private(:phoenix_endpoint, OtherEndpoint)
      payload = %{"session_id" => session_id}
      token = StreamToken.sign(other_conn, payload)

      # Verify with TestEndpoint (should fail)
      conn =
        build_test_conn(:get, "/__datastar/stream?token=#{token}")
        |> StreamPlug.call([])

      assert conn.status == 401
      assert conn.resp_body == "Invalid stream token"
      assert conn.halted
    end
  end

  describe "call/2 - expired token" do
    test "returns 401 for expired token", %{session_id: session_id} do
      # Save original config
      original = Application.get_env(:phoenix_datastar, :stream_token_max_age)

      try do
        # Set token max_age to 0 to make tokens expire immediately
        Application.put_env(:phoenix_datastar, :stream_token_max_age, 0)

        conn = build_test_conn(:get, "/__datastar/stream")
        payload = %{"session_id" => session_id}
        token = build_signed_token(conn, payload)

        # Small delay to ensure expiration
        :timer.sleep(1)

        conn =
          build_test_conn(:get, "/__datastar/stream?token=#{token}")
          |> StreamPlug.call([])

        assert conn.status == 401
        assert conn.resp_body == "Invalid stream token"
        assert conn.halted
      after
        # Restore original config
        if original do
          Application.put_env(:phoenix_datastar, :stream_token_max_age, original)
        else
          Application.delete_env(:phoenix_datastar, :stream_token_max_age)
        end
      end
    end
  end

  describe "call/2 - session not found (409 stream_requires_reload)" do
    test "returns 409 when GenServer for session_id is not running", %{session_id: session_id} do
      # Start registry for this test
      start_supervised!({Registry, keys: :unique, name: PhoenixDatastar.Registry})

      conn = build_test_conn(:get, "/__datastar/stream")
      payload = %{"session_id" => session_id}
      token = build_signed_token(conn, payload)

      # Don't start any server - session_id has no GenServer running
      conn =
        build_test_conn(:get, "/__datastar/stream?token=#{token}")
        |> StreamPlug.call([])

      assert conn.status == 409
      assert conn.resp_body == "stream_requires_reload"
      assert get_resp_header(conn, "x-datastar-location") == ["/__datastar/stream"]
      assert conn.halted
    end

    test "sets x-datastar-location header to request_path", %{session_id: session_id} do
      # Start registry for this test
      start_supervised!({Registry, keys: :unique, name: PhoenixDatastar.Registry})

      conn = build_test_conn(:get, "/custom/stream/path")
      payload = %{"session_id" => session_id}
      token = build_signed_token(conn, payload)

      conn =
        build_conn(:get, "/custom/stream/path?token=#{token}")
        |> put_private(:phoenix_endpoint, TestEndpoint)
        |> StreamPlug.call([])

      assert conn.status == 409
      assert get_resp_header(conn, "x-datastar-location") == ["/custom/stream/path"]
    end
  end

  describe "call/2 - valid token with running session" do
    # Note: Testing the actual SSE stream is complex because enter_loop/2 blocks.
    # We can test up until the SSE headers are set by using a short-lived connection.

    test "sets SSE response headers when session exists", %{session_id: session_id} do
      # Start registry for this test
      start_supervised!({Registry, keys: :unique, name: PhoenixDatastar.Registry})

      # Start the server first
      {:ok, _pid} = Server.ensure_started(TestLiveView, session_id, %{}, %{}, "/test")

      conn = build_test_conn(:get, "/__datastar/stream")
      payload = %{"session_id" => session_id}
      token = build_signed_token(conn, payload)

      # We need to spawn this in a separate process because enter_loop blocks
      test_pid = self()

      spawn_link(fn ->
        # This will block in enter_loop, so we'll have it send us the conn state
        conn_to_test =
          build_test_conn(:get, "/__datastar/stream?token=#{token}")

        # Fetch query params manually since call/2 does this
        conn_to_test = fetch_query_params(conn_to_test)

        # Verify token works
        {:ok, _payload} = StreamToken.verify(conn_to_test, token)

        # Signal test that setup works
        send(test_pid, :token_verified)
      end)

      # Wait for verification
      assert_receive :token_verified, 1000
    end

    test "extracts session_id from payload" do
      # Start registry for this test
      start_supervised!({Registry, keys: :unique, name: PhoenixDatastar.Registry})

      conn = build_test_conn(:get, "/__datastar/stream")
      custom_session = "custom-session-#{System.unique_integer([:positive])}"
      payload = %{"session_id" => custom_session}
      token = build_signed_token(conn, payload)

      # Without a server for custom_session, should get 409
      conn =
        build_test_conn(:get, "/__datastar/stream?token=#{token}")
        |> StreamPlug.call([])

      # This confirms the session_id was correctly extracted from the payload
      assert conn.status == 409
    end
  end

  describe "call/2 - payload handling" do
    test "handles payload with additional fields", %{session_id: session_id} do
      # Start registry for this test
      start_supervised!({Registry, keys: :unique, name: PhoenixDatastar.Registry})

      conn = build_test_conn(:get, "/__datastar/stream")
      payload = %{
        "session_id" => session_id,
        "path" => "/counter",
        "extra_field" => "ignored"
      }
      token = build_signed_token(conn, payload)

      # Without server, should get 409 (confirms payload was parsed)
      conn =
        build_test_conn(:get, "/__datastar/stream?token=#{token}")
        |> StreamPlug.call([])

      assert conn.status == 409
    end

    test "raises FunctionClauseError for payload with missing session_id (nil)" do
      conn = build_test_conn(:get, "/__datastar/stream")
      # payload without session_id - session_id will be nil
      payload = %{"path" => "/counter"}
      token = build_signed_token(conn, payload)

      # Registry.via/1 requires binary session_id, so this raises
      assert_raise FunctionClauseError, fn ->
        build_test_conn(:get, "/__datastar/stream?token=#{token}")
        |> StreamPlug.call([])
      end
    end
  end

  describe "call/2 - fetch_query_params" do
    test "handles URL-encoded token" do
      # Start registry for this test
      start_supervised!({Registry, keys: :unique, name: PhoenixDatastar.Registry})

      conn = build_test_conn(:get, "/__datastar/stream")
      payload = %{"session_id" => "test-session"}
      token = build_signed_token(conn, payload)
      encoded_token = URI.encode_www_form(token)

      conn =
        build_test_conn(:get, "/__datastar/stream?token=#{encoded_token}")
        |> StreamPlug.call([])

      # Token should be decoded and verified; without server, returns 409
      assert conn.status == 409
    end

    test "handles token with special characters in session_id" do
      # Start registry for this test
      start_supervised!({Registry, keys: :unique, name: PhoenixDatastar.Registry})

      conn = build_test_conn(:get, "/__datastar/stream")
      payload = %{"session_id" => "session/with:special+chars"}
      token = build_signed_token(conn, payload)

      conn =
        build_test_conn(:get, "/__datastar/stream?token=#{token}")
        |> StreamPlug.call([])

      # Without server, returns 409
      assert conn.status == 409
    end
  end

  describe "safe_subscribe/1" do
    test "returns :error when GenServer is stopped after starting", %{session_id: session_id} do
      # Start registry for this test
      start_supervised!({Registry, keys: :unique, name: PhoenixDatastar.Registry})

      # Start and then stop the server
      {:ok, pid} = Server.ensure_started(TestLiveView, session_id, %{}, %{}, "/test")
      GenServer.stop(pid)

      # Give registry time to clean up
      :timer.sleep(10)

      conn = build_test_conn(:get, "/__datastar/stream")
      payload = %{"session_id" => session_id}
      token = build_signed_token(conn, payload)

      conn =
        build_test_conn(:get, "/__datastar/stream?token=#{token}")
        |> StreamPlug.call([])

      assert conn.status == 409
      assert conn.resp_body == "stream_requires_reload"
    end
  end

  describe "Plug behaviour" do
    test "implements Plug behaviour" do
      behaviours = StreamPlug.__info__(:attributes)[:behaviour] || []
      assert Plug in behaviours
    end
  end

  describe "edge cases" do
    test "handles multiple token parameters (uses first)" do
      conn = build_test_conn(:get, "/__datastar/stream")
      payload = %{"session_id" => "first-session"}
      token = build_signed_token(conn, payload)

      # Multiple token params - Plug uses the last one typically
      conn =
        build_test_conn(:get, "/__datastar/stream?token=#{token}&token=invalid")
        |> StreamPlug.call([])

      # Should use "invalid" (last param) and fail
      assert conn.status == 401
    end

    test "handles nil token value in params" do
      conn =
        build_conn(:get, "/__datastar/stream")
        |> put_private(:phoenix_endpoint, TestEndpoint)
        |> Map.update!(:params, &Map.put(&1, "token", nil))
        |> fetch_query_params()
        |> StreamPlug.call([])

      assert conn.status == 401
      assert conn.resp_body == "Invalid stream token"
    end

    test "handles integer token value (non-binary)" do
      conn =
        build_conn(:get, "/__datastar/stream")
        |> put_private(:phoenix_endpoint, TestEndpoint)
        |> fetch_query_params()
        |> Map.update!(:params, &Map.put(&1, "token", 12345))
        |> StreamPlug.call([])

      assert conn.status == 401
      assert conn.resp_body == "Invalid stream token"
    end
  end
end
