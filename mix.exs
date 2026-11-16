defmodule AshBackendDrivenOptimisticUi.MixProject do
  use Mix.Project

  @source_url "https://github.com/Undeadlol1/ash_backend_driven_optimistic_ui"
  @version "0.1.0"

  def project do
    [
      app: :ash_backend_driven_optimistic_ui,
      version: @version,
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      aliases: aliases(),
      docs: &docs/0,
      description: description(),
      package: package(),
      name: "AshBackendDrivenOptimisticUi",
      source_url: @source_url
    ]
  end

  def application do
    [extra_applications: [:logger, :crypto]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:ash, "~> 3.22"},
      {:spark, "~> 2.3"},
      {:ash_json_api, "~> 1.0", optional: true},
      {:jason, "~> 1.4"},
      # Only for `AshBackendDrivenOptimisticUi.Test`: it subscribes to the host's PubSub and
      # matches `Phoenix.Socket.Broadcast`, which ships in `phoenix`.
      {:phoenix, "~> 1.7", optional: true},
      # Ash needs a SAT solver to evaluate policies.
      {:picosat_elixir, "~> 0.2", only: :test},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      # For `mix igniter.install` and `mix spark.cheat_sheets`.
      {:igniter, "~> 0.6", optional: true}
    ]
  end

  defp aliases do
    [
      "spark.formatter": "spark.formatter --extensions AshBackendDrivenOptimisticUi.Resource",
      "spark.cheat_sheets": "spark.cheat_sheets --extensions AshBackendDrivenOptimisticUi.Resource",
      docs: ["spark.cheat_sheets", "docs"]
    ]
  end

  defp docs do
    [
      main: "readme",
      before_closing_body_tag: &before_closing_body_tag/1,
      source_ref: "v#{@version}",
      extras: [
        {"README.md", title: "Home"},
        "documentation/topics/how-it-works.md",
        "documentation/topics/on-the-wire.md",
        "documentation/topics/examples.md",
        "documentation/topics/expressions.md",
        "documentation/topics/testing.md",
        {"documentation/dsls/DSL-AshBackendDrivenOptimisticUi.Resource.md",
         search_data: Spark.Docs.search_data_for(AshBackendDrivenOptimisticUi.Resource)},
        "CHANGELOG.md"
      ],
      groups_for_extras: [
        Topics: ~r"documentation/topics",
        Reference: ~r"documentation/dsls",
        "About AshBackendDrivenOptimisticUi": ["CHANGELOG.md"]
      ],
      groups_for_modules: [
        "Public API": [
          AshBackendDrivenOptimisticUi.Resource,
          AshBackendDrivenOptimisticUi.Registry,
          AshBackendDrivenOptimisticUi.RuleSet,
          AshBackendDrivenOptimisticUi.PushCollector,
          AshBackendDrivenOptimisticUi.Test,
          AshBackendDrivenOptimisticUi.NotOptimistic,
          AshBackendDrivenOptimisticUi.Info
        ],
        "Rules and reactions": [
          AshBackendDrivenOptimisticUi.Rule,
          AshBackendDrivenOptimisticUi.Reaction
        ],
        Effects: [
          AshBackendDrivenOptimisticUi.Effect,
          AshBackendDrivenOptimisticUi.Effect.Set,
          AshBackendDrivenOptimisticUi.Effect.Push,
          AshBackendDrivenOptimisticUi.Effect.Where,
          AshBackendDrivenOptimisticUi.Effect.Insert,
          AshBackendDrivenOptimisticUi.Effect.Remove,
          AshBackendDrivenOptimisticUi.Effect.Edit,
          AshBackendDrivenOptimisticUi.Effect.Clear
        ],
        "How it works": [
          AshBackendDrivenOptimisticUi.Rules,
          AshBackendDrivenOptimisticUi.Compiler,
          AshBackendDrivenOptimisticUi.JsonLogic,
          AshBackendDrivenOptimisticUi.PushId,
          AshBackendDrivenOptimisticUi.Snapshot,
          AshBackendDrivenOptimisticUi.Resource.Transformers.DeriveSets,
          AshBackendDrivenOptimisticUi.Resource.Verifiers.ValidateRules
        ],
        "Mix tasks": [
          Mix.Tasks.AshBackendDrivenOptimisticUi.Install,
          Mix.Tasks.OptimisticUi.Explain,
          Mix.Tasks.OptimisticUi.Snapshot
        ]
      ]
    ]
  end

  defp description do
    "Ash extension: declare what a write changes, and clients can show it before the server answers."
  end

  # Draws ```mermaid blocks as diagrams.
  defp before_closing_body_tag(:html) do
    """
    <script defer src="https://cdn.jsdelivr.net/npm/mermaid@11.4.1/dist/mermaid.min.js"></script>
    <script>
      let initialized = false;
      window.addEventListener("exdoc:loaded", () => {
        if (!initialized) {
          mermaid.initialize({
            startOnLoad: false,
            theme: document.body.className.includes("dark") ? "dark" : "default"
          });
          initialized = true;
        }
        let id = 0;
        for (const codeEl of document.querySelectorAll("pre code.mermaid")) {
          const preEl = codeEl.parentElement;
          const graphEl = document.createElement("div");
          mermaid.render("mermaid-graph-" + id++, codeEl.textContent).then(({svg, bindFunctions}) => {
            graphEl.innerHTML = svg;
            bindFunctions?.(graphEl);
            preEl.insertAdjacentElement("afterend", graphEl);
            preEl.remove();
          });
        }
      });
    </script>
    """
  end

  defp before_closing_body_tag(_format), do: ""

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib documentation .formatter.exs mix.exs README.md CHANGELOG.md LICENSE usage-rules.md)
    ]
  end
end
