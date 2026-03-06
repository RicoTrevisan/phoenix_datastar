locals_without_parens = [
  datastar: 2,
  datastar: 3,
  datastar_session: 2,
  datastar_session: 3
]

# Used by "mix format"
[
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  locals_without_parens: locals_without_parens,
  export: [locals_without_parens: locals_without_parens]
]
