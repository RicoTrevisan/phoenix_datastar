defmodule PhoenixDatastar.HelpersTest do
  use ExUnit.Case

  alias PhoenixDatastar.Helpers
  alias PhoenixDatastar.Socket

  # Mock view module for testing render_html
  defmodule TestView do
    def render(assigns) do
      {:safe, "<div>Hello #{assigns[:name] || "World"}</div>"}
    end
  end

  # Nested module for testing get_view_name
  defmodule MyApp.Web.Views.CounterStar do
  end

  describe "get_session_map/1" do
    test "returns empty map when plug_session is not set" do
      conn = %Plug.Conn{
        private: %{},
        assigns: %{layout: {SomeLayout, :app}}
      }

      result = Helpers.get_session_map(conn)

      assert result == %{"flash" => %{}}
    end

    test "merges session and assigns when plug_session is set" do
      # Create a conn with plug_session and assigns
      conn =
        Plug.Test.conn(:get, "/")
        |> Plug.Conn.put_private(:plug_session, %{"user_id" => 123})
        |> Plug.Conn.assign(:current_user, %{name: "Alice"})

      result = Helpers.get_session_map(conn)

      assert result["current_user"] == %{name: "Alice"}
      assert result["flash"] == %{}
    end

    test "stringifies assign keys" do
      conn = %Plug.Conn{
        private: %{},
        assigns: %{
          current_user: %{name: "Alice"},
          current_scope: :admin,
          layout: {SomeLayout, :app}
        }
      }

      result = Helpers.get_session_map(conn)

      assert result["current_user"] == %{name: "Alice"}
      assert result["current_scope"] == :admin
      refute Map.has_key?(result, :current_user)
      refute Map.has_key?(result, :current_scope)
    end

    test "drops layout from assigns" do
      conn = %Plug.Conn{
        private: %{},
        assigns: %{
          layout: {SomeLayout, :app},
          other_key: "value"
        }
      }

      result = Helpers.get_session_map(conn)

      refute Map.has_key?(result, "layout")
      refute Map.has_key?(result, :layout)
      assert result["other_key"] == "value"
    end

    test "provides default flash when not present" do
      conn = %Plug.Conn{
        private: %{},
        assigns: %{}
      }

      result = Helpers.get_session_map(conn)

      assert result["flash"] == %{}
    end

    test "preserves existing flash from assigns" do
      conn = %Plug.Conn{
        private: %{},
        assigns: %{
          flash: %{info: "Welcome!", error: "Something went wrong"}
        }
      }

      result = Helpers.get_session_map(conn)

      assert result["flash"] == %{info: "Welcome!", error: "Something went wrong"}
    end

    test "handles empty assigns" do
      conn = %Plug.Conn{
        private: %{},
        assigns: %{}
      }

      result = Helpers.get_session_map(conn)

      assert result == %{"flash" => %{}}
    end

    test "assigns override session values with same key" do
      # Assigns are merged on top of session, so assigns take precedence
      conn =
        Plug.Test.conn(:get, "/")
        |> Plug.Conn.put_private(:plug_session, %{"user_id" => 123, "role" => "guest"})
        |> Plug.Conn.assign(:role, :admin)

      result = Helpers.get_session_map(conn)

      # The assign value should override the session value
      assert result["role"] == :admin
    end
  end

  describe "get_view_name/1" do
    test "extracts the last part of a simple module" do
      assert Helpers.get_view_name(CounterStar) == "CounterStar"
    end

    test "extracts the last part of a nested module" do
      assert Helpers.get_view_name(MyApp.Web.Views.CounterStar) == "CounterStar"
    end

    test "handles deeply nested modules" do
      defmodule Very.Deeply.Nested.Module.Name do
      end

      assert Helpers.get_view_name(Very.Deeply.Nested.Module.Name) == "Name"
    end

    test "returns full name for single-level module" do
      defmodule SimpleModule do
      end

      assert Helpers.get_view_name(SimpleModule) == "SimpleModule"
    end

    test "handles Elixir prefix modules correctly" do
      # Module names internally have Elixir. prefix but Module.split handles this
      assert Helpers.get_view_name(Elixir.String) == "String"
    end
  end

  describe "render_html/2" do
    test "renders view with socket assigns" do
      socket = %Socket{
        view: TestView,
        assigns: %{name: "Alice"}
      }

      result = Helpers.render_html(TestView, socket)

      assert result == {:safe, "<div>Hello Alice</div>"}
    end

    test "renders view with empty assigns" do
      socket = %Socket{
        view: TestView,
        assigns: %{}
      }

      result = Helpers.render_html(TestView, socket)

      assert result == {:safe, "<div>Hello World</div>"}
    end

    test "passes all assigns to render function" do
      defmodule MultiAssignView do
        def render(assigns) do
          {:safe, "Name: #{assigns[:name]}, Count: #{assigns[:count]}"}
        end
      end

      socket = %Socket{
        view: MultiAssignView,
        assigns: %{name: "Bob", count: 42}
      }

      result = Helpers.render_html(MultiAssignView, socket)

      assert result == {:safe, "Name: Bob, Count: 42"}
    end

    test "does not pass signals to render function" do
      defmodule SignalCheckView do
        def render(assigns) do
          has_signals = Map.has_key?(assigns, :signals)
          {:safe, "Has signals key: #{has_signals}"}
        end
      end

      socket = %Socket{
        view: SignalCheckView,
        assigns: %{name: "Test"},
        signals: %{count: 5}
      }

      result = Helpers.render_html(SignalCheckView, socket)

      # Signals should not be in assigns
      assert result == {:safe, "Has signals key: false"}
    end
  end
end
