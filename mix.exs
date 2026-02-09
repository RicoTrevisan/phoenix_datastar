defmodule PhoenixDatastar.MixProject do
  use Mix.Project

  @version "0.1.6"
  @source_url "https://github.com/RicoTrevisan/phoenix_datastar"

  def project do
    [
      app: :phoenix_datastar,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
      docs: docs(),
      name: "PhoenixDatastar",
      description:
        "A LiveView-like experience for Phoenix using Datastar's SSE + Signals architecture",
      source_url: @source_url,
      homepage_url: @source_url
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto]
    ]
  end

  defp deps do
    [
      {:phoenix, "~> 1.7"},
      {:phoenix_html, "~> 4.0"},
      {:phoenix_live_view, "~> 1.0"},
      {:plug, "~> 1.14"},
      {:jason, "~> 1.4"},
      {:igniter, "~> 0.5", optional: true},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      maintainers: ["Rico Trevisan"],
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url
      },
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE),
      keywords: ["phoenix", "datastar", "sse", "hypermedia", "htmx"]
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "LICENSE"],
      source_ref: "v#{@version}",
      source_url: @source_url
    ]
  end
end
