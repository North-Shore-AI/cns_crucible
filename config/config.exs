import Config

# Prevent CrucibleFramework from starting a database repo during tests/examples.
config :crucible_framework,
  enable_repo: false,
  backends: %{
    tinkex: Crucible.Backend.Tinkex
  },
  stage_registry: %{
    data_load: Crucible.Stage.DataLoad,
    data_checks: Crucible.Stage.DataChecks,
    guardrails: Crucible.Stage.Guardrails,
    backend_call: Crucible.Stage.BackendCall,
    cns_surrogate_validation: Crucible.Stage.CNSSurrogateValidation,
    cns_tda_validation: Crucible.Stage.CNSTDAValidation,
    cns_metrics: Crucible.Stage.CNSMetrics,
    bench: Crucible.Stage.Bench,
    report: Crucible.Stage.Report
  },
  cns_adapter: CnsExperiments.Adapters.Metrics,
  cns_surrogate_adapter: CnsExperiments.Adapters.Surrogates,
  cns_tda_adapter: CnsExperiments.Adapters.TDA,
  guardrail_adapter: Crucible.Stage.Guardrails.Noop

# Provide a minimal repo config to silence connection attempts when the application boots.
config :crucible_framework, CrucibleFramework.Repo,
  database: "placeholder",
  username: "postgres",
  password: "postgres",
  hostname: "localhost"
