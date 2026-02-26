defmodule PhoenixDatastar.ActionsTest do
  use ExUnit.Case, async: true

  import PhoenixDatastar.Actions
  import Phoenix.LiveViewTest

  test "navigate/2 builds nav post action" do
    action = navigate("/dashboard/orgs")

    assert action =~ "@post($nav_path"
    assert action =~ "to: '/dashboard/orgs'"
    assert action =~ "nav_token: $nav_token"
    assert action =~ "evt.preventDefault()"
  end

  test "navigate/2 supports replace mode" do
    action = navigate("/dashboard/orgs", replace: true)
    assert action =~ "mode: 'replace'"
  end

  test "ds_link emits click handler with explicit preventDefault" do
    html =
      render_component(&ds_link/1, %{
        navigate: "/dashboard/orgs",
        inner_block: [%{inner_block: fn _, _ -> "Organizations" end}]
      })

    assert html =~ "data-on:click="
    assert html =~ "evt.preventDefault()"
  end
end
