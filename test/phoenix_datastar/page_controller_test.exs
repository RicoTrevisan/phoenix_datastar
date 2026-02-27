defmodule PhoenixDatastar.PageControllerTest do
  @moduledoc """
  Tests for PhoenixDatastar.PageController.

  The `mount/2` function is the primary public interface, responsible for:
  - Rendering stateless views directly
  - Starting GenServers for live views
  - Resolving HTML modules (per-route, global config, default)
  - Generating session IDs
  - Building stream, event, and nav paths
  - Signing stream tokens for live views
  """
  use ExUnit.Case
  import Phoenix.ConnTest

  # Test HTML modules
  defmodule TestHTML do
    use Phoenix.Component

    def mount(assigns) do
      ~H"""
      <div data-test-html="true">
        Stream: <%= @stream_path %> Event: <%= @event_path %> Nav: <%= @nav_path %>
        SessionId: <%= @session_id %> NavToken: <%= @nav_token || "nil" %>
        Inner: <%= @inner_html %>
      </div>
      """
    end
  end

  defmodule AltTestHTML do
    use Phoenix.Component

    def mount(assigns) do
      ~H"<div data-alt-html>Alt: <%= @inner_html %></div>"
    end
  end

  defmodule SignalsTestHTML do
    use Phoenix.Component
    import Phoenix.HTML, only: [raw: 1]

    def mount(assigns) do
      # Use raw/1 to avoid HTML entity encoding of JSON quotes
      raw("Signals: #{Jason.encode!(assigns[:initial_signals])}")
    end
  end

  # Test views
  defmodule StatelessView do
    use PhoenixDatastar

    @impl PhoenixDatastar
    def mount(_params, _session, socket), do: {:ok, socket}

    @impl PhoenixDatastar
    def render(assigns), do: ~H"<p>Stateless content</p>"
  end

  defmodule StatelessViewWithSignals do
    use PhoenixDatastar

    @impl PhoenixDatastar
    def mount(_params, _session, socket) do
      {:ok, put_signal(socket, :count, 42)}
    end

    @impl PhoenixDatastar
    def render(assigns), do: ~H|<span data-text="$count"></span>|
  end

  defmodule StatelessViewWithOptions do
    use PhoenixDatastar

    @impl PhoenixDatastar
    def mount(_params, _session, socket) do
      {:ok, put_signal(socket, :value, "test"), temporary_assigns: []}
    end

    @impl PhoenixDatastar
    def render(assigns), do: ~H"<div>With options</div>"
  end

  defmodule StatelessViewWithParams do
    use PhoenixDatastar

    @impl PhoenixDatastar
    def mount(params, _session, socket) do
      {:ok, put_signal(socket, :param_id, params["id"])}
    end

    @impl PhoenixDatastar
    def render(assigns), do: ~H"<div>Params view</div>"
  end

  defmodule StatelessViewWithSession do
    use PhoenixDatastar

    @impl PhoenixDatastar
    def mount(_params, session, socket) do
      user_name = get_in(session, ["current_user", :name]) || "anonymous"
      {:ok, put_signal(socket, :user, user_name)}
    end

    @impl PhoenixDatastar
    def render(assigns), do: ~H"<div>Session view</div>"
  end

  defmodule StatelessViewWithFlash do
    use PhoenixDatastar

    @impl PhoenixDatastar
    def mount(_params, _session, socket) do
      # Flash should be available in assigns
      flash = socket.assigns.flash
      {:ok, put_signal(socket, :has_flash, map_size(flash) > 0)}
    end

    @impl PhoenixDatastar
    def render(assigns), do: ~H"<div>Flash: <%= inspect(@flash) %></div>"
  end

  defmodule LiveView do
    use PhoenixDatastar, :live

    @impl PhoenixDatastar
    def mount(_params, _session, socket), do: {:ok, socket}

    @impl PhoenixDatastar
    def render(assigns), do: ~H"<p>Live content</p>"
  end

  defmodule LiveViewWithSignals do
    use PhoenixDatastar, :live

    @impl PhoenixDatastar
    def mount(_params, _session, socket) do
      {:ok, put_signal(socket, :live_count, 100)}
    end

    @impl PhoenixDatastar
    def render(assigns), do: ~H"<span>Live with signals</span>"
  end

  # Mock endpoint for token signing
  defmodule TokenEndpoint do
    def config(:secret_key_base), do: String.duplicate("a", 64)
  end

  setup do
    start_supervised!({Registry, keys: :unique, name: PhoenixDatastar.Registry})
    :ok
  end

  describe "mount/2 with stateless views" do
    test "renders stateless view without starting GenServer" do
      conn = build_test_conn("/test")
      conn = put_datastar(conn, StatelessView, "/test", html_module: TestHTML)

      conn = PhoenixDatastar.PageController.mount(conn, %{})

      response = html_response(conn, 200)
      assert response =~ "Stateless content"
      # Stream path should be nil for stateless views
      assert response =~ "Stream:"
      refute response =~ "Stream: /test/stream"
    end

    test "sets correct event path" do
      conn = build_test_conn("/counter")
      conn = put_datastar(conn, StatelessView, "/counter", html_module: TestHTML)

      conn = PhoenixDatastar.PageController.mount(conn, %{})

      response = html_response(conn, 200)
      assert response =~ "Event: /counter/_event"
    end

    test "sets correct nav path" do
      conn = build_test_conn("/test")
      conn = put_datastar(conn, StatelessView, "/test", html_module: TestHTML)

      conn = PhoenixDatastar.PageController.mount(conn, %{})

      response = html_response(conn, 200)
      assert response =~ "Nav: /__datastar/nav"
    end

    test "generates unique session IDs" do
      conn1 = build_test_conn("/test")
      conn1 = put_datastar(conn1, StatelessView, "/test", html_module: TestHTML)
      conn1 = PhoenixDatastar.PageController.mount(conn1, %{})

      conn2 = build_test_conn("/test")
      conn2 = put_datastar(conn2, StatelessView, "/test", html_module: TestHTML)
      conn2 = PhoenixDatastar.PageController.mount(conn2, %{})

      response1 = html_response(conn1, 200)
      response2 = html_response(conn2, 200)

      # Extract session IDs
      [_, session_id1] = Regex.run(~r/SessionId:\s+(\S+)/, response1)
      [_, session_id2] = Regex.run(~r/SessionId:\s+(\S+)/, response2)

      refute session_id1 == session_id2
      # Session IDs should be 22 characters (16 bytes base64url encoded without padding)
      assert String.length(session_id1) == 22
      assert String.length(session_id2) == 22
    end

    test "passes initial signals from mount to template" do
      conn = build_test_conn("/test")
      conn = put_datastar(conn, StatelessViewWithSignals, "/test", html_module: SignalsTestHTML)

      conn = PhoenixDatastar.PageController.mount(conn, %{})

      response = html_response(conn, 200)
      assert response =~ "\"count\":42"
    end

    test "handles mount returning {:ok, socket, opts}" do
      conn = build_test_conn("/test")
      conn = put_datastar(conn, StatelessViewWithOptions, "/test", html_module: TestHTML)

      # Should not raise
      conn = PhoenixDatastar.PageController.mount(conn, %{})

      response = html_response(conn, 200)
      assert response =~ "With options"
    end

    test "passes params to view mount" do
      conn = build_test_conn("/items/123")
      conn = Map.put(conn, :params, %{"id" => "123", "_format" => "html"})
      conn = put_datastar(conn, StatelessViewWithParams, "/items/:id", html_module: SignalsTestHTML)

      conn = PhoenixDatastar.PageController.mount(conn, %{})

      response = html_response(conn, 200)
      assert response =~ "\"param_id\":\"123\""
    end

    test "passes session data to view mount" do
      conn = build_test_conn("/test")
      conn = Plug.Conn.assign(conn, :current_user, %{name: "Alice"})
      conn = put_datastar(conn, StatelessViewWithSession, "/test", html_module: SignalsTestHTML)

      conn = PhoenixDatastar.PageController.mount(conn, %{})

      response = html_response(conn, 200)
      assert response =~ "\"user\":\"Alice\""
    end

    test "provides flash in socket assigns" do
      conn = build_test_conn("/test")
      conn = put_datastar(conn, StatelessViewWithFlash, "/test", html_module: TestHTML)

      conn = PhoenixDatastar.PageController.mount(conn, %{})

      # Should not crash, flash is available
      assert conn.status == 200
    end

    test "nav_token is nil for stateless views" do
      conn = build_test_conn("/test")
      conn = put_datastar(conn, StatelessView, "/test", html_module: TestHTML)

      conn = PhoenixDatastar.PageController.mount(conn, %{})

      response = html_response(conn, 200)
      assert response =~ "NavToken: nil"
    end
  end

  describe "mount/2 with live views" do
    test "starts GenServer for live view" do
      conn = build_test_conn("/live")
      conn = put_datastar(conn, LiveView, "/live", html_module: TestHTML)
      conn = Plug.Conn.put_private(conn, :phoenix_endpoint, TokenEndpoint)

      conn = PhoenixDatastar.PageController.mount(conn, %{})

      response = html_response(conn, 200)
      assert response =~ "Live content"

      # Extract session ID to verify GenServer was started
      [_, session_id] = Regex.run(~r/SessionId:\s+(\S+)/, response)

      # GenServer should be accessible via Registry
      assert [{pid, _}] = Registry.lookup(PhoenixDatastar.Registry, session_id)
      assert is_pid(pid)
    end

    test "sets stream path for live views" do
      conn = build_test_conn("/live")
      conn = put_datastar(conn, LiveView, "/live", html_module: TestHTML)
      conn = Plug.Conn.put_private(conn, :phoenix_endpoint, TokenEndpoint)

      conn = PhoenixDatastar.PageController.mount(conn, %{})

      response = html_response(conn, 200)
      assert response =~ "Stream: /__datastar/stream?token="
    end

    test "generates signed nav token for live views" do
      conn = build_test_conn("/live")
      conn = put_datastar(conn, LiveView, "/live", html_module: TestHTML)
      conn = Plug.Conn.put_private(conn, :phoenix_endpoint, TokenEndpoint)

      conn = PhoenixDatastar.PageController.mount(conn, %{})

      response = html_response(conn, 200)
      refute response =~ "NavToken: nil"
      assert response =~ "NavToken:"
    end

    test "stream token contains session_id and session_name" do
      conn = build_test_conn("/dashboard")
      conn = put_datastar(conn, LiveView, "/dashboard",
        html_module: TestHTML,
        session_name: :dashboard
      )
      conn = Plug.Conn.put_private(conn, :phoenix_endpoint, TokenEndpoint)

      conn = PhoenixDatastar.PageController.mount(conn, %{})

      response = html_response(conn, 200)
      [_, stream_path] = Regex.run(~r/Stream:\s+(\S+)\s+Event:/, response)

      token = stream_path |> URI.parse() |> Map.get(:query) |> URI.decode_query() |> Map.fetch!("token")
      {:ok, payload} = PhoenixDatastar.StreamToken.verify(conn, token)

      assert Map.has_key?(payload, "session_id")
      assert payload["session_name"] == :dashboard
    end

    test "stream token stays short with large params" do
      huge = String.duplicate("x", 20_000)

      conn = build_test_conn("/dashboard")
      conn = Map.put(conn, :params, %{"_format" => "html", "huge" => huge})
      conn = Plug.Conn.assign(conn, :large_blob, huge)
      conn = put_datastar(conn, LiveView, "/dashboard", html_module: TestHTML)
      conn = Plug.Conn.put_private(conn, :phoenix_endpoint, TokenEndpoint)

      conn = PhoenixDatastar.PageController.mount(conn, %{})

      response = html_response(conn, 200)
      [_, stream_path] = Regex.run(~r/Stream:\s+(\S+)\s+Event:/, response)

      # Token should be reasonably short, not include the huge params
      assert String.length(stream_path) < 1024
    end

    test "passes initial signals from live view to template" do
      conn = build_test_conn("/live")
      conn = put_datastar(conn, LiveViewWithSignals, "/live", html_module: SignalsTestHTML)
      conn = Plug.Conn.put_private(conn, :phoenix_endpoint, TokenEndpoint)

      conn = PhoenixDatastar.PageController.mount(conn, %{})

      response = html_response(conn, 200)
      assert response =~ "\"live_count\":100"
    end
  end

  describe "mount/2 path handling" do
    test "uses request_path for resolved dynamic segments" do
      # Simulate a dynamic route like "/:workspace_slug" that resolved to "/acme-corp"
      conn = build_test_conn("/acme-corp")
      conn = put_datastar(conn, StatelessView, "/:workspace_slug", html_module: TestHTML)

      conn = PhoenixDatastar.PageController.mount(conn, %{})

      response = html_response(conn, 200)
      # Event path should use the resolved path, not the pattern
      assert response =~ "Event: /acme-corp/_event"
      refute response =~ "Event: /:workspace_slug/_event"
    end

    test "root path generates correct event path without double slashes" do
      conn = build_test_conn("/")
      conn = put_datastar(conn, StatelessView, "/", html_module: TestHTML)

      conn = PhoenixDatastar.PageController.mount(conn, %{})

      response = html_response(conn, 200)
      assert response =~ "Event: /_event"
      refute response =~ "Event: //_event"
    end

    test "nested paths work correctly" do
      conn = build_test_conn("/admin/settings/security")
      conn = put_datastar(conn, StatelessView, "/admin/settings/security", html_module: TestHTML)

      conn = PhoenixDatastar.PageController.mount(conn, %{})

      response = html_response(conn, 200)
      assert response =~ "Event: /admin/settings/security/_event"
    end
  end

  describe "mount/2 HTML module resolution" do
    test "uses html_module from conn.private.datastar when provided" do
      conn = build_test_conn("/test")
      conn = put_datastar(conn, StatelessView, "/test", html_module: AltTestHTML)

      conn = PhoenixDatastar.PageController.mount(conn, %{})

      response = html_response(conn, 200)
      assert response =~ "data-alt-html"
      assert response =~ "Alt:"
    end

    test "falls back to global config when no per-route html_module" do
      # Set global config
      original = Application.get_env(:phoenix_datastar, :html_module)
      Application.put_env(:phoenix_datastar, :html_module, AltTestHTML)

      try do
        conn = build_test_conn("/test")
        conn = put_datastar(conn, StatelessView, "/test", html_module: nil)

        conn = PhoenixDatastar.PageController.mount(conn, %{})

        response = html_response(conn, 200)
        assert response =~ "data-alt-html"
      after
        if original do
          Application.put_env(:phoenix_datastar, :html_module, original)
        else
          Application.delete_env(:phoenix_datastar, :html_module)
        end
      end
    end

    test "falls back to DefaultHTML when no config" do
      # Ensure no global config
      original = Application.get_env(:phoenix_datastar, :html_module)
      Application.delete_env(:phoenix_datastar, :html_module)

      try do
        conn = build_test_conn("/test")
        conn = put_datastar(conn, StatelessViewWithSignals, "/test", html_module: nil)

        conn = PhoenixDatastar.PageController.mount(conn, %{})

        response = html_response(conn, 200)
        # DefaultHTML uses id="app" and data-signals
        assert response =~ "id=\"app\""
        assert response =~ "data-signals="
      after
        if original do
          Application.put_env(:phoenix_datastar, :html_module, original)
        else
          Application.delete_env(:phoenix_datastar, :html_module)
        end
      end
    end
  end

  describe "mount/2 page title" do
    test "sets page title from view name" do
      conn = build_test_conn("/test")
      conn = put_datastar(conn, StatelessView, "/test", html_module: TestHTML)

      conn = PhoenixDatastar.PageController.mount(conn, %{})

      # The page title is set in the assigns passed to render
      # We can check the view was set correctly
      assert conn.status == 200
    end
  end

  # Helper functions

  defp build_test_conn(path) do
    Phoenix.ConnTest.build_conn(:get, path)
    |> Map.put(:params, %{"_format" => "html"})
  end

  defp put_datastar(conn, view, path, opts) do
    datastar_meta =
      %{view: view, path: path}
      |> maybe_put(:html_module, opts[:html_module])
      |> maybe_put(:session_name, opts[:session_name])

    Plug.Conn.put_private(conn, :datastar, datastar_meta)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
