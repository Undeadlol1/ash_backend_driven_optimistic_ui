import Config

config :ash,
  read_action_after_action_hooks_in_order?: true,
  default_string_length_count: :codepoints,
  policies: [no_filter_static_forbidden_reads?: false]

config :ash_backend_driven_optimistic_ui,
  otp_app: :ash_backend_driven_optimistic_ui,
  ash_domains: [AshBackendDrivenOptimisticUi.TestSupport.SampleDomain],
  pubsub: AshBackendDrivenOptimisticUi.TestPubSub
