spark_locals_without_parens = [
  at: 1,
  because: 1,
  clear: 0,
  clear: 1,
  edit: 0,
  edit: 1,
  from: 1,
  insert: 0,
  insert: 1,
  into: 1,
  not_optimistic: 1,
  not_optimistic: 2,
  on: 1,
  on: 2,
  optimistic: 1,
  optimistic: 2,
  payload: 1,
  push: 1,
  push: 2,
  push: 3,
  remove: 0,
  remove: 1,
  set: 2,
  set: 3,
  where: 1,
  where: 2
]

[
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  import_deps: [:ash],
  line_length: 122,
  locals_without_parens: spark_locals_without_parens,
  export: [locals_without_parens: spark_locals_without_parens]
]
