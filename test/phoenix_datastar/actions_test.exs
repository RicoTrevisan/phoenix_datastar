defmodule PhoenixDatastar.ActionsTest do
  use ExUnit.Case, async: true

  import PhoenixDatastar.Actions
  import Phoenix.LiveViewTest

  test "navigate/2 builds nav post action with query params" do
    action = navigate("/dashboard/orgs")

    assert action =~ "@post('/__datastar/nav?_ds_to=%2Fdashboard%2Forgs&_ds_mode=push'"
    assert action =~ "evt.preventDefault()"
  end

  test "navigate/2 supports replace mode" do
    action = navigate("/dashboard/orgs", replace: true)
    assert action =~ "_ds_mode=replace"
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
