defmodule Ecall.Control.MixProject do
  use Mix.Project

  @version "0.0.2"
  def project do
    [
      app: :ecall_control,
      version: @version,
      elixir: "~> 1.7",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:mix_test_watch, "~> 0.8", only: :dev, runtime: false},
      {:gen_state_machine, "~> 2.0"},
      {:circuits_uart, "~> 1.2"}
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"},
    ]
  end
  defp package() do
    [
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => "https://github.com/nadsat/ecall_control"}
    ]
  end
end
