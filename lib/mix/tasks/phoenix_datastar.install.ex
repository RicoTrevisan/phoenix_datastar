defmodule Mix.Tasks.PhoenixDatastar.Install do
  @moduledoc """
  Installs PhoenixDatastar into your Phoenix application.

  ## Usage

      mix phoenix_datastar.install

  This will:
  1. Add the Registry to your application's supervision tree
  2. Configure the HTML module for PhoenixDatastar
  3. Create the DatastarHTML module

  You will also receive instructions for manual steps:
  - Adding the Datastar JavaScript to your layout
  - Importing the router macro
  """

  use Igniter.Mix.Task

  @impl Igniter.Mix.Task
  def info(_argv, _composing_task) do
    %Igniter.Mix.Task.Info{
      group: :phoenix_datastar,
      example: "mix phoenix_datastar.install"
    }
  end

  @impl Igniter.Mix.Task
  def igniter(igniter) do
    web_module = Igniter.Libs.Phoenix.web_module(igniter)
    html_module = Module.concat(web_module, DatastarHTML)

    web_module_path =
      web_module |> Module.split() |> Enum.map(&Macro.underscore/1) |> Path.join()

    igniter
    |> add_registry_to_supervision_tree()
    |> configure_html_module(html_module)
    |> create_datastar_html_module(html_module)
    |> add_manual_step_notices(web_module_path)
  end

  defp add_registry_to_supervision_tree(igniter) do
    Igniter.Project.Application.add_new_child(
      igniter,
      {Registry, [keys: :unique, name: PhoenixDatastar.Registry]}
    )
  end

  defp configure_html_module(igniter, html_module) do
    Igniter.Project.Config.configure_new(
      igniter,
      "config.exs",
      :phoenix_datastar,
      [:html_module],
      html_module
    )
  end

  defp create_datastar_html_module(igniter, html_module) do
    Igniter.Project.Module.create_module(igniter, html_module, """
    use Phoenix.Component

    def mount(assigns) do
      ~H\"\"\"
      <div
        id={"ds-live-\#{@session_id}"}
        data-signals={"{session_id: '\#{@session_id}'}"}
        data-init__once={"@get('\#{@stream_path}', {openWhenHidden: true})"}
      >
        {@inner_html}
      </div>
      \"\"\"
    end
    """)
  end

  defp add_manual_step_notices(igniter, web_module_path) do
    igniter
    |> Igniter.add_notice("""
    Add the Datastar JavaScript to your layout's <head> in lib/#{web_module_path}/components/layouts/root.html.heex:

        <script
          type="module"
          src="https://cdn.jsdelivr.net/gh/starfederation/datastar@1.0.0-RC.7/bundles/datastar.js"
        ></script>
    """)
    |> Igniter.add_notice("""
    Import the router macro in your router (lib/#{web_module_path}/router.ex):

        import PhoenixDatastar.Router

    Then add routes like:

        datastar "/counter", CounterStar
    """)
  end
end
