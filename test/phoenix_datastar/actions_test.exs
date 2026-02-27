defmodule PhoenixDatastar.ActionsTest do
  use ExUnit.Case, async: true

  import PhoenixDatastar.Actions
  import Phoenix.LiveViewTest

  describe "event/1 and event/2" do
    test "generates a @post action with event name and CSRF header" do
      action = event("increment")

      assert action =~ "@post($event_path+'/increment'"
      assert action =~ "session_id: $session_id"
      assert action =~ "headers: {'x-csrf-token': document.querySelector('meta[name=csrf-token]').content}"
    end

    test "includes options in the request body" do
      action = event("toggle_code", "name: 'counter'")

      assert action =~ "@post($event_path+'/toggle_code'"
      assert action =~ "name: 'counter'"
      assert action =~ "session_id: $session_id"
    end
  end

  describe "navigate/1 and navigate/2" do
    test "builds nav post action with push mode by default" do
      action = navigate("/dashboard/orgs")

      assert action =~ "@post('/__datastar/nav?_ds_to=%2Fdashboard%2Forgs&_ds_mode=push'"
      assert action =~ "evt.preventDefault()"
    end

    test "supports replace mode" do
      action = navigate("/dashboard/orgs", replace: true)

      assert action =~ "_ds_mode=replace"
      refute action =~ "_ds_mode=push"
    end

    test "checks for modifier keys before preventing default" do
      action = navigate("/test")

      assert action =~ "evt.metaKey"
      assert action =~ "evt.ctrlKey"
      assert action =~ "evt.shiftKey"
      assert action =~ "evt.altKey"
      assert action =~ "evt.button !== 0"
    end
  end

  describe "ds_link/1" do
    test "emits click handler with href for soft navigation" do
      html =
        render_component(&ds_link/1, %{
          navigate: "/dashboard/orgs",
          inner_block: [%{inner_block: fn _, _ -> "Organizations" end}]
        })

      assert html =~ "data-on:click="
      assert html =~ "evt.preventDefault()"
      assert html =~ ~s(href="/dashboard/orgs")
      assert html =~ "Organizations"
    end

    test "supports replace mode" do
      html =
        render_component(&ds_link/1, %{
          navigate: "/dashboard/orgs",
          replace: true,
          inner_block: [%{inner_block: fn _, _ -> "Organizations" end}]
        })

      assert html =~ "_ds_mode=replace"
    end

    test "with method :hard does not emit click handler" do
      html =
        render_component(&ds_link/1, %{
          navigate: "/other",
          method: :hard,
          inner_block: [%{inner_block: fn _, _ -> "Full Reload" end}]
        })

      assert html =~ ~s(href="/other")
      refute html =~ "data-on:click="
    end

    test "passes through global attributes" do
      html =
        render_component(&ds_link/1, %{
          navigate: "/test",
          class: "btn btn-primary",
          id: "my-link",
          inner_block: [%{inner_block: fn _, _ -> "Link" end}]
        })

      assert html =~ ~s(class="btn btn-primary")
      assert html =~ ~s(id="my-link")
    end
  end
end
