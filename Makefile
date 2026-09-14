.PHONY: fmt test

fmt:
	cargo fmt
	ocamlformat --inplace ml/*.ml

# Official PL/Python tests (REL_16_STABLE), translated in sql/ + expected/,
# are executed by the `sql_regression` host test. One command runs the Rust
# #[pg_test] suite, host tests, and SQL:
#
#   cargo pgrx test --no-default-features --features pg_test,pg16
#
# `cargo pgrx test` enables the `pg_test` feature itself; listing it here is
# explicit. Do not pass `pg_test` as a trailing positional argument — cargo
# treats that as a test-name filter and skips host tests.
PG ?= 16
test:
	cargo pgrx test --no-default-features --features pg_test,pg$(PG)
