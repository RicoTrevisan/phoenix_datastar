defmodule Mix.Tasks.PhoenixDatastar.Install do
  @moduledoc """
  Installs PhoenixDatastar into your Phoenix application.

  ## Usage

      mix phoenix_datastar.install

  This will:
  1. Add the Registry to your application's supervision tree
  2. Configure the HTML module for PhoenixDatastar
  3. Enable stripping of debug annotations in dev (for SSE patches)
  4. Create the DatastarHTML module
  5. Add `import PhoenixDatastar.Router` to your router
  6. Add `"sse"` to the browser pipeline's `:accepts` plug
  7. Add `def live_sse` and `def datastar` to your web module
  8. Add the Datastar JavaScript to your root layout
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
    |> configure_strip_debug_annotations()
    |> create_datastar_html_module(html_module)
    |> add_router_import()
    |> add_sse_to_browser_pipeline()
    |> add_live_sse_to_web_module(web_module)
    |> add_datastar_script_to_layout(web_module_path)
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

  defp configure_strip_debug_annotations(igniter) do
    Igniter.Project.Config.configure_new(
      igniter,
      "dev.exs",
      :phoenix_datastar,
      [:strip_debug_annotations],
      true
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
        data-init__once={@stream_path && "@get('\#{@stream_path}', {openWhenHidden: true})"}
      >
        {@inner_html}
      </div>
      \"\"\"
    end
    """)
  end

  defp add_sse_to_browser_pipeline(igniter) do
    {igniter, router} = Igniter.Libs.Phoenix.select_router(igniter)

    if router do
      Igniter.Project.Module.find_and_update_module!(igniter, router, fn zipper ->
        # Find the browser pipeline
        with {:ok, zipper} <-
               Igniter.Code.Function.move_to_function_call_in_current_scope(
                 zipper,
                 :pipeline,
                 2,
                 &Igniter.Code.Function.argument_equals?(&1, 0, :browser)
               ),
             {:ok, zipper} <- Igniter.Code.Common.move_to_do_block(zipper),
             # Find plug :accepts inside the pipeline
             {:ok, zipper} <-
               Igniter.Code.Function.move_to_function_call_in_current_scope(
                 zipper,
                 :plug,
                 2,
                 &Igniter.Code.Function.argument_equals?(&1, 0, :accepts)
               ),
             {:ok, zipper} <- Igniter.Code.Function.move_to_nth_argument(zipper, 1),
             {:ok, zipper} <- Igniter.Code.List.append_new_to_list(zipper, "sse") do
          {:ok, zipper}
        else
          _ ->
            {:warning,
             "Could not add \"sse\" to plug :accepts in browser pipeline. Please add it manually."}
        end
      end)
    else
      Igniter.add_warning(
        igniter,
        "Could not find router. Please add \"sse\" to plug :accepts in browser pipeline manually."
      )
    end
  end

  defp add_live_sse_to_web_module(igniter, web_module) do
    live_sse_code = """
    def live_sse do
      quote do
        use PhoenixDatastar, :live
        import PhoenixDatastar.Actions

        unquote(html_helpers())
      end
    end

    def datastar do
      quote do
        use PhoenixDatastar
        import PhoenixDatastar.Actions

        unquote(html_helpers())
      end
    end
    """

    Igniter.Project.Module.find_and_update_module!(igniter, web_module, fn zipper ->
      # Check if live_sse already exists
      case Igniter.Code.Function.move_to_def(zipper, :live_sse, 0) do
        {:ok, _} ->
          # Already exists
          {:ok, zipper}

        :error ->
          # Find def live_view to add after it, using target: :at to get the def itself
          with {:ok, zipper} <-
                 Igniter.Code.Function.move_to_def(zipper, :live_view, 0, target: :at) do
            {:ok, Igniter.Code.Common.add_code(zipper, live_sse_code, placement: :after)}
          else
            :error ->
              # Try to find def controller to add after
              case Igniter.Code.Function.move_to_def(zipper, :controller, 0, target: :at) do
                {:ok, zipper} ->
                  {:ok, Igniter.Code.Common.add_code(zipper, live_sse_code, placement: :after)}

                :error ->
                  {:warning,
                   "Could not find a suitable location to add `def live_sse`. Please add it manually to your web module."}
              end
          end
      end
    end)
  end

  defp add_datastar_script_to_layout(igniter, web_module_path) do
    layout_path = "lib/#{web_module_path}/components/layouts/root.html.heex"

    script_tag = """
        <script
          type="module"
          src="https://cdn.jsdelivr.net/gh/starfederation/datastar@1.0.0-RC.7/bundles/datastar.js"
        ></script>
    """

    Igniter.update_file(igniter, layout_path, fn source ->
      content = Rewrite.Source.get(source, :content)

      if String.contains?(content, "datastar.js") do
        # Already has the script
        source
      else
        case String.split(content, "</head>", parts: 2) do
          [before_head, after_head] ->
            new_content = before_head <> script_tag <> "  </head>" <> after_head
            Rewrite.Source.update(source, :content, new_content)

          _ ->
            # Couldn't find </head>, return unchanged
            source
        end
      end
    end)
  end

  defp add_router_import(igniter) do
    {igniter, router} = Igniter.Libs.Phoenix.select_router(igniter)

    if router do
      Igniter.Project.Module.find_and_update_module!(igniter, router, fn zipper ->
        with {:ok, zipper} <- Igniter.Libs.Phoenix.move_to_router_use(igniter, zipper) do
          import_code = "import PhoenixDatastar.Router"

          # Check if import already exists in the module
          case Igniter.Code.Function.move_to_function_call_in_current_scope(
                 zipper,
                 :import,
                 1,
                 &Igniter.Code.Function.argument_equals?(&1, 0, PhoenixDatastar.Router)
               ) do
            {:ok, _} ->
              # Import already exists
              {:ok, zipper}

            :error ->
              # Add import after the use statement
              {:ok, Igniter.Code.Common.add_code(zipper, import_code, placement: :after)}
          end
        else
          _ ->
            {:warning,
             "Could not add `import PhoenixDatastar.Router` to your router. Please add it manually."}
        end
      end)
    else
      Igniter.add_warning(
        igniter,
        "Could not find a router. Please add `import PhoenixDatastar.Router` manually."
      )
    end
  end

  defp add_manual_step_notices(igniter, web_module_path) do
    igniter
    |> Igniter.add_notice("""
    Add routes in your router (lib/#{web_module_path}/router.ex):

        datastar "/counter", CounterStar
    """)
  end
end
