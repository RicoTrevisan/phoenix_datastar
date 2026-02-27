defmodule PhoenixDatastar.SignalsTest do
  use ExUnit.Case

  alias PhoenixDatastar.Signals
  alias PhoenixDatastar.SSE

  describe "read/1" do
    test "reads signals from GET request query params" do
      conn = %Plug.Conn{
        method: "GET",
        query_params: %{"datastar" => ~s({"count": 10, "name": "test"})}
      }

      assert Signals.read(conn) == %{"count" => 10, "name" => "test"}
    end

    test "returns empty map when no signals in GET request" do
      conn = %Plug.Conn{method: "GET", query_params: %{}}
      assert Signals.read(conn) == %{}
    end

    test "reads signals from POST request body params" do
      conn = %Plug.Conn{
        method: "POST",
        body_params: %{"count" => 5, "action" => "increment"}
      }

      assert Signals.read(conn) == %{"count" => 5, "action" => "increment"}
    end

    test "handles invalid JSON gracefully" do
      conn = %Plug.Conn{
        method: "GET",
        query_params: %{"datastar" => "not valid json"}
      }

      assert Signals.read(conn) == %{}
    end

    test "handles nil and empty string in GET datastar param" do
      assert Signals.read(%Plug.Conn{method: "GET", query_params: %{"datastar" => nil}}) == %{}
      assert Signals.read(%Plug.Conn{method: "GET", query_params: %{"datastar" => ""}}) == %{}
    end
  end

  describe "patch/3 and patch_raw/3" do
    setup do
      {:ok, agent} = Agent.start_link(fn -> [] end)

      mock_conn = %Plug.Conn{
        adapter: {__MODULE__.MockAdapter, agent},
        state: :chunked
      }

      sse = SSE.new(mock_conn)
      {:ok, sse: sse, agent: agent}
    end

    test "sends patch event with encoded signals", %{sse: sse, agent: agent} do
      result = Signals.patch(sse, %{count: 42, message: "Hello"})

      assert %SSE{} = result
      [chunk] = Agent.get(agent, & &1)
      assert chunk =~ "event: datastar-patch-signals"
      assert chunk =~ "data: signals "
      assert chunk =~ "count"
      assert chunk =~ "42"
    end

    test "only_if_missing option adds data line", %{sse: sse, agent: agent} do
      Signals.patch(sse, %{value: 100}, only_if_missing: true)

      [chunk] = Agent.get(agent, & &1)
      assert chunk =~ "data: onlyIfMissing true"
      assert chunk =~ "data: signals "
    end

    test "event_id and retry options pass through", %{sse: sse, agent: agent} do
      Signals.patch(sse, %{data: "test"}, event_id: "evt-123", retry: 5000)

      [chunk] = Agent.get(agent, & &1)
      assert chunk =~ "id: evt-123"
      assert chunk =~ "retry: 5000"
    end

    test "patch_raw sends raw JSON string directly", %{sse: sse, agent: agent} do
      Signals.patch_raw(sse, ~s({"count": 42}))

      [chunk] = Agent.get(agent, & &1)
      assert chunk =~ "event: datastar-patch-signals"
      assert chunk =~ ~s(data: signals {"count": 42})
    end

    test "can chain patch and patch_raw calls", %{sse: sse, agent: agent} do
      sse
      |> Signals.patch(%{encoded: true})
      |> Signals.patch_raw(~s({"raw": true}))
      |> Signals.patch(%{final: true})

      assert length(Agent.get(agent, & &1)) == 3
    end
  end

  defmodule MockAdapter do
    @behaviour Plug.Conn.Adapter

    @impl true
    def send_chunked(agent, _status, _headers), do: {:ok, nil, agent}

    @impl true
    def chunk(agent, body) do
      Agent.update(agent, fn chunks -> chunks ++ [body] end)
      {:ok, nil, agent}
    end

    @impl true
    def send_resp(_agent, _status, _headers, _body), do: raise("not implemented")
    @impl true
    def send_file(_agent, _status, _headers, _path, _offset, _length), do: raise("not implemented")
    @impl true
    def read_req_body(_agent, _opts), do: raise("not implemented")
    @impl true
    def inform(_agent, _status, _headers), do: raise("not implemented")
    @impl true
    def push(_agent, _path, _headers), do: raise("not implemented")
    @impl true
    def get_peer_data(_agent), do: raise("not implemented")
    @impl true
    def get_http_protocol(_agent), do: raise("not implemented")
    @impl true
    def upgrade(_agent, _protocol, _opts), do: raise("not implemented")
  end
end
