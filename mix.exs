defmodule ExBlofin.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/drdray1/ex_blofin"

  def project do
    [
      app: :ex_blofin,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
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

  defp deps do
    [
      {:req, "~> 0.5"},
      {:jason, "~> 1.4"},
      {:decimal, "~> 2.0"},
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
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE)
    ]
  end

  defp docs do
    [
      main: "ExBlofin",
      extras: ["README.md"],
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
          ExBlofin.Client
        ]
      ]
    ]
  end
end
