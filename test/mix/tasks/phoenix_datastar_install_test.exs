defmodule Mix.Tasks.PhoenixDatastar.InstallTest do
  use ExUnit.Case, async: true

  import Igniter.Test

  describe "info/2" do
    test "returns correct task info" do
      info = Mix.Tasks.PhoenixDatastar.Install.info([], nil)

      assert info.group == :phoenix_datastar
      assert info.example == "mix phoenix_datastar.install"
    end
  end

  describe "igniter/1 - full installation" do
    test "adds registry to supervision tree" do
      igniter =
        phx_test_project()
        |> Mix.Tasks.PhoenixDatastar.Install.igniter()

      assert_has_patch(igniter, "lib/test/application.ex", """
      + |{Registry, [keys: :unique, name: PhoenixDatastar.Registry]}
      """)
    end

    test "configures strip_debug_annotations in dev.exs" do
      igniter =
        phx_test_project()
        |> Mix.Tasks.PhoenixDatastar.Install.igniter()

      # The actual format uses keyword syntax
      assert_has_patch(igniter, "config/dev.exs", """
      + |config :phoenix_datastar, strip_debug_annotations: true
      """)
    end

    test "adds router import" do
      igniter =
        phx_test_project()
        |> Mix.Tasks.PhoenixDatastar.Install.igniter()

      assert_has_patch(igniter, "lib/test_web/router.ex", """
      + |  import PhoenixDatastar.Router
      """)
    end

    test "adds sse to browser pipeline accepts" do
      igniter =
        phx_test_project()
        |> Mix.Tasks.PhoenixDatastar.Install.igniter()

      # The actual format uses parentheses
      assert_has_patch(igniter, "lib/test_web/router.ex", """
      + |    plug(:accepts, ["html", "sse"])
      """)
    end

    test "adds live_datastar to web module" do
      igniter =
        phx_test_project()
        |> Mix.Tasks.PhoenixDatastar.Install.igniter()

      assert_has_patch(igniter, "lib/test_web.ex", """
      + |  def live_datastar do
      """)
    end

    test "adds datastar to web module" do
      igniter =
        phx_test_project()
        |> Mix.Tasks.PhoenixDatastar.Install.igniter()

      assert_has_patch(igniter, "lib/test_web.ex", """
      + |  def datastar do
      """)
    end

    test "adds PhoenixDatastar.Actions import to web module" do
      igniter =
        phx_test_project()
        |> Mix.Tasks.PhoenixDatastar.Install.igniter()

      assert_has_patch(igniter, "lib/test_web.ex", """
      + |      import PhoenixDatastar.Actions
      """)
    end

    test "adds __datastar scope to router" do
      igniter =
        phx_test_project()
        |> Mix.Tasks.PhoenixDatastar.Install.igniter()

      diff = Igniter.Test.diff(igniter, only: "lib/test_web/router.ex")

      assert diff =~ ~s(scope "/__datastar" do)
    end

    test "adds StreamPlug route to __datastar scope" do
      igniter =
        phx_test_project()
        |> Mix.Tasks.PhoenixDatastar.Install.igniter()

      diff = Igniter.Test.diff(igniter, only: "lib/test_web/router.ex")

      assert diff =~ "PhoenixDatastar.StreamPlug"
    end

    test "adds NavPlug route to __datastar scope" do
      igniter =
        phx_test_project()
        |> Mix.Tasks.PhoenixDatastar.Install.igniter()

      diff = Igniter.Test.diff(igniter, only: "lib/test_web/router.ex")

      assert diff =~ "PhoenixDatastar.NavPlug"
    end

    test "adds fetch_session and protect_from_forgery to __datastar scope" do
      igniter =
        phx_test_project()
        |> Mix.Tasks.PhoenixDatastar.Install.igniter()

      diff = Igniter.Test.diff(igniter, only: "lib/test_web/router.ex")

      assert diff =~ "fetch_session"
      assert diff =~ "protect_from_forgery"
    end

    test "adds datastar script to root layout" do
      igniter =
        phx_test_project()
        |> Mix.Tasks.PhoenixDatastar.Install.igniter()

      assert_has_patch(igniter, "lib/test_web/components/layouts/root.html.heex", """
      + |    <script
      """)
    end

    test "adds manual step notices" do
      igniter =
        phx_test_project()
        |> Mix.Tasks.PhoenixDatastar.Install.igniter()

      # Use a function matcher for notices (as shown in Igniter.Test implementation)
      assert_has_notice(igniter, fn notice ->
        String.contains?(notice, "Add routes in your router")
      end)
    end

    test "manual step notices include datastar_session example" do
      igniter =
        phx_test_project()
        |> Mix.Tasks.PhoenixDatastar.Install.igniter()

      assert_has_notice(igniter, fn notice ->
        String.contains?(notice, "datastar_session :default do")
      end)
    end

    test "manual step notices include html_module configuration" do
      igniter =
        phx_test_project()
        |> Mix.Tasks.PhoenixDatastar.Install.igniter()

      assert_has_notice(igniter, fn notice ->
        String.contains?(notice, ":html_module")
      end)
    end
  end

  describe "igniter/1 - idempotency" do
    test "running install twice results in no additional changes" do
      # First run: apply changes and get the resulting igniter
      first_run_igniter =
        phx_test_project()
        |> Mix.Tasks.PhoenixDatastar.Install.igniter()
        |> apply_igniter!()

      # Second run: run install again on the already-installed project
      second_run_igniter =
        first_run_igniter
        |> Mix.Tasks.PhoenixDatastar.Install.igniter()

      # Verify no changes on second run (for key files)
      assert_unchanged(second_run_igniter, "lib/test_web.ex")
      assert_unchanged(second_run_igniter, "lib/test_web/router.ex")
      assert_unchanged(second_run_igniter, "lib/test_web/components/layouts/root.html.heex")
    end

    test "live_datastar is not duplicated on second run" do
      first_run_igniter =
        phx_test_project()
        |> Mix.Tasks.PhoenixDatastar.Install.igniter()
        |> apply_igniter!()

      second_run_igniter =
        first_run_igniter
        |> Mix.Tasks.PhoenixDatastar.Install.igniter()

      # Web module should be unchanged
      assert_unchanged(second_run_igniter, "lib/test_web.ex")
    end

    test "router import is not duplicated on second run" do
      first_run_igniter =
        phx_test_project()
        |> Mix.Tasks.PhoenixDatastar.Install.igniter()
        |> apply_igniter!()

      second_run_igniter =
        first_run_igniter
        |> Mix.Tasks.PhoenixDatastar.Install.igniter()

      # Router should be unchanged
      assert_unchanged(second_run_igniter, "lib/test_web/router.ex")
    end

    test "datastar script is not duplicated on second run" do
      first_run_igniter =
        phx_test_project()
        |> Mix.Tasks.PhoenixDatastar.Install.igniter()
        |> apply_igniter!()

      second_run_igniter =
        first_run_igniter
        |> Mix.Tasks.PhoenixDatastar.Install.igniter()

      # Layout should be unchanged
      assert_unchanged(second_run_igniter, "lib/test_web/components/layouts/root.html.heex")
    end
  end

  describe "igniter/1 - edge cases" do
    test "adds live_datastar using PhoenixDatastar :live mode" do
      igniter =
        phx_test_project()
        |> Mix.Tasks.PhoenixDatastar.Install.igniter()

      assert_has_patch(igniter, "lib/test_web.ex", """
      + |      use PhoenixDatastar, :live
      """)
    end

    test "adds datastar using PhoenixDatastar without :live mode" do
      igniter =
        phx_test_project()
        |> Mix.Tasks.PhoenixDatastar.Install.igniter()

      # Check that regular datastar uses PhoenixDatastar without :live
      diff = Igniter.Test.diff(igniter, only: "lib/test_web.ex")

      # There should be both `use PhoenixDatastar, :live` and `use PhoenixDatastar` (without :live)
      assert diff =~ "use PhoenixDatastar, :live"
      assert diff =~ "use PhoenixDatastar\n"
    end

    test "includes html_helpers() in both live_datastar and datastar" do
      igniter =
        phx_test_project()
        |> Mix.Tasks.PhoenixDatastar.Install.igniter()

      assert_has_patch(igniter, "lib/test_web.ex", """
      + |      unquote(html_helpers())
      """)
    end
  end

  describe "igniter/1 - registry configuration" do
    test "registry uses unique keys and correct name" do
      igniter =
        phx_test_project()
        |> Mix.Tasks.PhoenixDatastar.Install.igniter()

      # Check that the full registry tuple is added correctly
      assert_has_patch(igniter, "lib/test/application.ex", """
      + |{Registry, [keys: :unique, name: PhoenixDatastar.Registry]}
      """)
    end
  end

  describe "igniter/1 - combined full scenario" do
    test "applies all changes in a fresh phoenix project" do
      igniter =
        phx_test_project()
        |> Mix.Tasks.PhoenixDatastar.Install.igniter()

      # Verify all major components are added
      diff = Igniter.Test.diff(igniter)

      # Registry in application
      assert diff =~ "Registry"
      assert diff =~ "PhoenixDatastar.Registry"

      # Config
      assert diff =~ "strip_debug_annotations"

      # Router changes
      assert diff =~ "import PhoenixDatastar.Router"
      assert diff =~ ~s("sse")
      assert diff =~ ~s(scope "/__datastar" do)
      assert diff =~ "PhoenixDatastar.StreamPlug"
      assert diff =~ "PhoenixDatastar.NavPlug"

      # Web module changes
      assert diff =~ "def live_datastar do"
      assert diff =~ "def datastar do"
      assert diff =~ "PhoenixDatastar.Actions"

      # Layout changes
      assert diff =~ "datastar.js"
    end

    test "all key files are modified" do
      igniter =
        phx_test_project()
        |> Mix.Tasks.PhoenixDatastar.Install.igniter()

      # Verify these files are changed (not unchanged)
      diff = Igniter.Test.diff(igniter)

      assert diff =~ "lib/test/application.ex"
      assert diff =~ "config/dev.exs"
      assert diff =~ "lib/test_web/router.ex"
      assert diff =~ "lib/test_web.ex"
      assert diff =~ "lib/test_web/components/layouts/root.html.heex"
    end
  end

  describe "igniter/1 - correct datastar CDN version" do
    test "uses correct datastar CDN URL" do
      igniter =
        phx_test_project()
        |> Mix.Tasks.PhoenixDatastar.Install.igniter()

      diff = Igniter.Test.diff(igniter, only: "lib/test_web/components/layouts/root.html.heex")

      assert diff =~ "cdn.jsdelivr.net"
      assert diff =~ "starfederation/datastar"
      assert diff =~ "datastar.js"
    end
  end

  describe "igniter/1 - script attributes" do
    test "script tag uses type=module" do
      igniter =
        phx_test_project()
        |> Mix.Tasks.PhoenixDatastar.Install.igniter()

      diff = Igniter.Test.diff(igniter, only: "lib/test_web/components/layouts/root.html.heex")

      assert diff =~ ~s(type="module")
    end
  end
end
