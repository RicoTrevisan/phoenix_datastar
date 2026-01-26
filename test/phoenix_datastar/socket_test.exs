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
      socket = Socket.assign(socket, :count, 0)

      assert socket.assigns.count == 0
    end

    test "overwrites existing assigns" do
      socket = %Socket{view: TestView, assigns: %{count: 0}}
      socket = Socket.assign(socket, :count, 10)

      assert socket.assigns.count == 10
    end
  end

  describe "assign/2" do
    test "assigns from a map" do
      socket = %Socket{view: TestView}
      socket = Socket.assign(socket, %{count: 0, name: "test"})

      assert socket.assigns.count == 0
      assert socket.assigns.name == "test"
    end

    test "assigns from a keyword list" do
      socket = %Socket{view: TestView}
      socket = Socket.assign(socket, count: 5, name: "foo")

      assert socket.assigns.count == 5
      assert socket.assigns.name == "foo"
    end
  end

  describe "update/3" do
    test "updates an assign with a function" do
      socket = %Socket{view: TestView, assigns: %{count: 5}}
      socket = Socket.update(socket, :count, &(&1 + 1))

      assert socket.assigns.count == 6
    end
  end

  describe "patch_elements/3" do
    test "queues a patch with a render function" do
      socket = %Socket{view: TestView, assigns: %{count: 5}}

      socket =
        Socket.patch_elements(socket, "#count", fn assigns ->
          {:safe, "<span>#{assigns.count}</span>"}
        end)

      assert length(socket.patches) == 1
      [{selector, html}] = socket.patches
      assert selector == "#count"
      assert html == "<span>5</span>"
    end

    test "queues a patch with raw HTML" do
      socket = %Socket{view: TestView}
      socket = Socket.patch_elements(socket, "#target", {:safe, "<div>content</div>"})

      assert length(socket.patches) == 1
      [{selector, html}] = socket.patches
      assert selector == "#target"
      assert html == "<div>content</div>"
    end

    test "accumulates multiple patches" do
      socket = %Socket{view: TestView}

      socket =
        socket
        |> Socket.patch_elements("#a", {:safe, "<span>a</span>"})
        |> Socket.patch_elements("#b", {:safe, "<span>b</span>"})

      assert length(socket.patches) == 2
    end
  end
end
