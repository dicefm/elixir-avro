# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- [[#14]]: Support for custom logical types.
- Record field `"default"` values. The generated `from_avro/1` fills a key the payload lacks from
  the field's default and decodes it like a given value; a key that is present wins. Only fields
  without a default are required, and only they are named in the `"Missing keys: …"` error.
  `to_avro/1` and the generated struct are unchanged. Supported: null, boolean, int, long, float,
  double, string, enum, array, map and union (by its first branch) defaults, logical types
  included. A record default, or union items in a non-empty array or map default, raises at
  generation time. erlavro cannot parse a default whose type is a named type from another schema
  file, so such a schema fails to load with a `:bad_default` error; a union default of `null`
  works with any other branches.

---

## [0.1.0] - 2024-03-28

First release


[Unreleased]: https://github.com/primait/auth0_ex/compare/0.1.0...HEAD
[0.1.0]: https://github.com/primait/elixir-avro/tree/0.1.0

[#14]: https://github.com/primait/elixir-avro/pull/14