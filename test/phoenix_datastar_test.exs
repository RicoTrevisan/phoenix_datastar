defmodule PhoenixDatastarTest do
  use ExUnit.Case

  defmodule StatelessView do
    use PhoenixDatastar

    @impl PhoenixDatastar
    def mount(_params, _session, socket), do: {:ok, socket}

    @impl PhoenixDatastar
    def render(_assigns), do: ""
  end

  defmodule LiveView do
    use PhoenixDatastar, :live

    @impl PhoenixDatastar
    def mount(_params, _session, socket), do: {:ok, socket}

    @impl PhoenixDatastar
    def render(_assigns), do: ""
  end

  defmodule LiveViewKeywordSyntax do
    use PhoenixDatastar, live: true

    @impl PhoenixDatastar
    def mount(_params, _session, socket), do: {:ok, socket}

    @impl PhoenixDatastar
    def render(_assigns), do: ""
  end

  defmodule ViewWithCustomHandlers do
    use PhoenixDatastar

    @impl PhoenixDatastar
    def mount(_params, _session, socket), do: {:ok, socket}

    @impl PhoenixDatastar
    def render(_assigns), do: ""

    @impl PhoenixDatastar
    def handle_event("custom", payload, socket) do
      {:noreply, Socket.assign(socket, :received, payload)}
    end

    @impl PhoenixDatastar
    def handle_info({:custom_msg, data}, socket) do
      {:noreply, Socket.assign(socket, :info_received, data)}
    end
  end

  describe "live?/1" do
    test "returns false for stateless views" do
      refute PhoenixDatastar.live?(StatelessView)
    end

    test "returns true for live views" do
      assert PhoenixDatastar.live?(LiveView)
      assert PhoenixDatastar.live?(LiveViewKeywordSyntax)
    end
  end

  describe "use PhoenixDatastar" do
    test "provides default handle_event/3 and handle_info/2" do
      socket = %PhoenixDatastar.Socket{view: StatelessView}

      assert StatelessView.handle_event("any_event", %{}, socket) == {:noreply, socket}
      assert StatelessView.handle_info(:any_message, socket) == {:noreply, socket}
    end

    test "allows overriding handle_event/3 and handle_info/2" do
      socket = %PhoenixDatastar.Socket{view: ViewWithCustomHandlers}

      {:noreply, s1} = ViewWithCustomHandlers.handle_event("custom", %{"key" => "value"}, socket)
      assert s1.assigns.received == %{"key" => "value"}

      {:noreply, s2} = ViewWithCustomHandlers.handle_info({:custom_msg, "hello"}, socket)
      assert s2.assigns.info_received == "hello"
    end
  end
end
