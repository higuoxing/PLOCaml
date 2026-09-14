.PHONY: fmt test

fmt:
	cargo fmt
	ocamlformat --inplace ml/*.ml

# Official PL/Python tests (REL_16_STABLE), translated in sql/ + expected/,
# are executed by the `sql_regression` host test. One command runs the Rust
# #[pg_test] suite, host tests, and SQL:
#
#   cargo pgrx test --no-default-features --features pg16
PG ?= 16
test:
	cargo pgrx test --no-default-features --features pg$(PG)
