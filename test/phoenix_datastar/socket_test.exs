defmodule PhoenixDatastar.SocketTest do
  use ExUnit.Case

  alias PhoenixDatastar.Socket

  defmodule TestView do
    use PhoenixDatastar

    @impl PhoenixDatastar
    def mount(_params, _session, socket), do: {:ok, socket}

    @impl PhoenixDatastar
    def render(_assigns), do: ""
  end

  describe "assign/3" do
    test "assigns a single key-value pair" do
      socket = %Socket{view: TestView}
      socket = Socket.assign(socket, :user, "Alice")

      assert socket.assigns.user == "Alice"
    end

    test "overwrites existing assigns" do
      socket = %Socket{view: TestView, assigns: %{user: "Alice"}}
      socket = Socket.assign(socket, :user, "Bob")

      assert socket.assigns.user == "Bob"
    end

    test "does not affect signals" do
      socket = %Socket{view: TestView, signals: %{count: 0}}
      socket = Socket.assign(socket, :user, "Alice")

      assert socket.assigns.user == "Alice"
      assert socket.signals == %{count: 0}
    end
  end

  describe "assign/2" do
    test "assigns from a map" do
      socket = %Socket{view: TestView}
      socket = Socket.assign(socket, %{user: "Alice", role: :admin})

      assert socket.assigns.user == "Alice"
      assert socket.assigns.role == :admin
    end

    test "assigns from a keyword list" do
      socket = %Socket{view: TestView}
      socket = Socket.assign(socket, user: "Alice", role: :admin)

      assert socket.assigns.user == "Alice"
      assert socket.assigns.role == :admin
    end
  end

  describe "update/3" do
    test "updates an assign with a function" do
      socket = %Socket{view: TestView, assigns: %{visits: 5}}
      socket = Socket.update(socket, :visits, &(&1 + 1))

      assert socket.assigns.visits == 6
    end
  end

  describe "put_signal/3" do
    test "puts a single signal" do
      socket = %Socket{view: TestView}
      socket = Socket.put_signal(socket, :count, 0)

      assert socket.signals.count == 0
    end

    test "overwrites existing signals" do
      socket = %Socket{view: TestView, signals: %{count: 0}}
      socket = Socket.put_signal(socket, :count, 10)

      assert socket.signals.count == 10
    end

    test "does not affect assigns" do
      socket = %Socket{view: TestView, assigns: %{user: "Alice"}}
      socket = Socket.put_signal(socket, :count, 0)

      assert socket.signals.count == 0
      assert socket.assigns.user == "Alice"
    end
  end

  describe "put_signal/2" do
    test "puts signals from a map" do
      socket = %Socket{view: TestView}
      socket = Socket.put_signal(socket, %{count: 0, name: "test"})

      assert socket.signals.count == 0
      assert socket.signals.name == "test"
    end

    test "puts signals from a keyword list" do
      socket = %Socket{view: TestView}
      socket = Socket.put_signal(socket, count: 5, name: "foo")

      assert socket.signals.count == 5
      assert socket.signals.name == "foo"
    end
  end

  describe "update_signal/3" do
    test "updates a signal with a function" do
      socket = %Socket{view: TestView, signals: %{count: 5}}
      socket = Socket.update_signal(socket, :count, &(&1 + 1))

      assert socket.signals.count == 6
    end
  end

  describe "patch_elements/3" do
    test "queues a patch with a render function that receives only assigns" do
      socket = %Socket{view: TestView, assigns: %{name: "Alice"}, signals: %{count: 5}}

      socket =
        Socket.patch_elements(socket, "#greeting", fn assigns ->
          # Render function receives assigns, not signals
          refute Map.has_key?(assigns, :count)
          {:safe, "<span>Hello #{assigns.name}</span>"}
        end)

      assert length(socket.events) == 1
      [{:patch, selector, html}] = socket.events
      assert selector == "#greeting"
      assert html == "<span>Hello Alice</span>"
    end

    test "queues a patch with raw HTML" do
      socket = %Socket{view: TestView}
      socket = Socket.patch_elements(socket, "#target", {:safe, "<div>content</div>"})

      assert length(socket.events) == 1
      [{:patch, selector, html}] = socket.events
      assert selector == "#target"
      assert html == "<div>content</div>"
    end

    test "accumulates multiple patches" do
      socket = %Socket{view: TestView}

      socket =
        socket
        |> Socket.patch_elements("#a", {:safe, "<span>a</span>"})
        |> Socket.patch_elements("#b", {:safe, "<span>b</span>"})

      assert length(socket.events) == 2
    end
  end
end
