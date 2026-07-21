defmodule ExBlofin.MixProject do
  use Mix.Project

  @version "0.2.0"
  @source_url "https://github.com/drdray1/ex_blofin"

  def project do
    [
      app: :ex_blofin,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      test_coverage: test_coverage(),
      elixirc_paths: elixirc_paths(Mix.env()),

      # Hex
      description: "Elixir client for the BloFin crypto derivatives API",
      package: package(),

      # Docs
      name: "ExBlofin",
      source_url: @source_url,
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto],
      mod: {ExBlofin.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # `mix test --cover` fails below the threshold.
  #
  # ExBlofin.Terminal.* is excluded: it is the interactive TUI behind the demo
  # scripts (~3,350 lines of ANSI rendering and polling loops), not part of the
  # API client. Including it would drag the figure down to roughly 28% and make
  # the number say more about the demos than the library.
  defp test_coverage do
    [
      # Note the threshold lives under :summary — a top-level :threshold key is
      # silently ignored, which reads as passing when it is doing nothing.
      summary: [threshold: 88],
      ignore_modules: [~r/^ExBlofin\.Terminal\./]
    ]
  end

  defp deps do
    [
      {:req, "~> 0.5"},
      {:jason, "~> 1.4"},
      {:decimal, "~> 2.0 or ~> 3.0"},
      {:websockex, "~> 0.4"},
      {:plug, "~> 1.14"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:mimic, "~> 1.7", only: :test}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib .formatter.exs mix.exs README.md CHANGELOG.md LICENSE)
    ]
  end

  defp docs do
    [
      main: "ExBlofin",
      extras: ["README.md", "CHANGELOG.md"],
      groups_for_modules: [
        "REST API": [
          ExBlofin.MarketData,
          ExBlofin.Account,
          ExBlofin.Asset,
          ExBlofin.Trading,
          ExBlofin.CopyTrading,
          ExBlofin.Affiliate,
          ExBlofin.User,
          ExBlofin.Tax
        ],
        Authentication: [
          ExBlofin.Auth
        ],
        WebSocket: [
          ExBlofin.WebSocket.Message,
          ExBlofin.WebSocket.Client,
          ExBlofin.WebSocket.PublicConnection,
          ExBlofin.WebSocket.PrivateConnection,
          ExBlofin.WebSocket.CopyTradingConnection
        ],
        Client: [
          ExBlofin.Client,
          ExBlofin.Paths
        ]
      ]
    ]
  end
end
