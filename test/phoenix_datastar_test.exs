defmodule PhoenixDatastarTest do
  use ExUnit.Case

  describe "live?/1" do
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

    test "returns false for stateless views" do
      refute PhoenixDatastar.live?(StatelessView)
    end

    test "returns true for live views" do
      assert PhoenixDatastar.live?(LiveView)
    end
  end
end
