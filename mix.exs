defmodule Genesis.MixProject do
  use Mix.Project

  @version "0.5.1"
  @url "https://github.com/thiagomajesk/genesis"

  def project do
    [
      app: :genesis,
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      package: package(),
      description: description()
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp description() do
    """
    An Entity Component System (ECS) for Elixir focused on easy of use and ergonomics.
    """
  end

  defp package do
    [
      maintainers: ["Thiago Majesk Goulart"],
      licenses: ["AGPL-3.0-only"],
      links: %{"GitHub" => @url},
      files: ~w(lib mix.exs README.md)
    ]
  end

  defp docs() do
    [
      main: "README",
      source_ref: "v#{@version}",
      source_url: @url,
      extras: [
        "README.md": [filename: "README"]
      ]
    ]
  end

  def application do
    [
      mod: {Genesis, []},
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:ex_doc, "~> 0.37", only: :dev, runtime: false}
    ]
  end
end
