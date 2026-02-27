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

  describe "new/4" do
    test "creates socket with standard assigns" do
      socket = Socket.new("session123", TestView, "/counter")

      assert socket.id == "session123"
      assert socket.view == TestView
      assert socket.assigns.session_id == "session123"
      assert socket.assigns.base_path == "/counter"
      assert socket.assigns.stream_path == "/counter/stream"
      assert socket.assigns.event_path == "/counter/_event"
      assert socket.assigns.flash == %{}
      assert socket.signals == %{}
      assert socket.events == []
    end

    test "creates non-live socket with live: false" do
      socket = Socket.new("session123", TestView, "/about", live: false)

      assert socket.assigns.stream_path == nil
      assert socket.assigns.event_path == "/about/_event"
    end

    test "handles root base path" do
      socket = Socket.new("session123", TestView, "/")

      assert socket.assigns.stream_path == "/stream"
      assert socket.assigns.event_path == "/_event"
    end
  end

  describe "assign/3 and assign/2" do
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

  describe "put_signal/3 and put_signal/2" do
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
          refute Map.has_key?(assigns, :count)
          {:safe, "<span>Hello #{assigns.name}</span>"}
        end)

      assert [{:patch, "#greeting", "<span>Hello Alice</span>"}] = socket.events
    end

    test "queues a patch with raw HTML" do
      socket = %Socket{view: TestView}
      socket = Socket.patch_elements(socket, "#target", {:safe, "<div>content</div>"})

      assert [{:patch, "#target", "<div>content</div>"}] = socket.events
    end

    test "accumulates multiple patches" do
      socket = %Socket{view: TestView}

      socket =
        socket
        |> Socket.patch_elements("#a", {:safe, "<span>a</span>"})
        |> Socket.patch_elements("#b", {:safe, "<span>b</span>"})

      assert length(socket.events) == 2
    end

    test "converts iodata to binary" do
      socket = %Socket{view: TestView}
      socket = Socket.patch_elements(socket, "#target", {:safe, ["<div>", "content", "</div>"]})

      [{:patch, _selector, html}] = socket.events
      assert html == "<div>content</div>"
    end
  end

  describe "execute_script/3" do
    test "queues a script event with options" do
      socket = %Socket{view: TestView}

      socket =
        socket
        |> Socket.execute_script("alert('Hello!')")
        |> Socket.execute_script("import {...}", attributes: %{type: "module"})

      assert [{:script, "alert('Hello!')", []}, {:script, "import {...}", [attributes: %{type: "module"}]}] =
               socket.events
    end
  end

  describe "redirect/3" do
    test "queues a redirect script" do
      socket = %Socket{view: TestView}
      socket = Socket.redirect(socket, "/dashboard")

      [{:script, script, _opts}] = socket.events
      assert script =~ "window.location='/dashboard'"
      assert script =~ "setTimeout"
    end
  end

  describe "console_log/3" do
    test "queues console.log with default level" do
      socket = %Socket{view: TestView}
      socket = Socket.console_log(socket, "Debug message")

      [{:script, script, _opts}] = socket.events
      assert script == "console.log('Debug message')"
    end

    test "supports all log levels" do
      for {level, method} <- [warn: "warn", error: "error", info: "info", debug: "debug"] do
        socket = %Socket{view: TestView}
        socket = Socket.console_log(socket, "msg", level: level)

        [{:script, script, _}] = socket.events
        assert script == "console.#{method}('msg')"
      end
    end

    test "encodes non-string messages as JSON" do
      socket = %Socket{view: TestView}
      socket = Socket.console_log(socket, [1, 2, 3])

      [{:script, script, _opts}] = socket.events
      assert script == "console.log([1,2,3])"
    end
  end

  describe "event ordering" do
    test "patches, scripts, and redirects accumulate in order" do
      socket = %Socket{view: TestView}

      socket =
        socket
        |> Socket.patch_elements("#a", {:safe, "<span>a</span>"})
        |> Socket.execute_script("console.log('test')")
        |> Socket.patch_elements("#b", {:safe, "<span>b</span>"})

      assert [{:patch, "#a", _}, {:script, _, _}, {:patch, "#b", _}] = socket.events
    end
  end

  describe "debug annotation stripping" do
    setup do
      original = Application.get_env(:phoenix_datastar, :strip_debug_annotations)
      on_exit(fn -> Application.put_env(:phoenix_datastar, :strip_debug_annotations, original) end)
      :ok
    end

    test "strips debug annotations when config is enabled" do
      Application.put_env(:phoenix_datastar, :strip_debug_annotations, true)

      socket = %Socket{view: TestView}

      html_with_annotations =
        {:safe,
         ~s|<!-- @caller lib/my_module.ex:10 --><div data-phx-loc="lib/my_module.ex:10">content</div>|}

      socket = Socket.patch_elements(socket, "#target", html_with_annotations)

      [{:patch, _selector, html}] = socket.events
      refute html =~ "@caller"
      refute html =~ "data-phx-loc"
      assert html =~ "<div>content</div>"
    end
  end
end
