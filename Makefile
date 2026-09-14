.PHONY: fmt installcheck regress install

# Ported official PL/Python regression tests (from PostgreSQL src/pl/plpython,
# adapted for PL/OCaml on the C main branch and reused here).
#
# REGRESS is the subset that the Rust implementation currently passes
# (or that only differed in error-message wording).
# REGRESS_XFAIL still requires missing features: SETOF, triggers,
# composite/record return, OUT/INOUT, void-Null checks.
REGRESS = \
	plocaml_schema \
	plocaml_populate \
	plocaml_spi \
	plocaml_do \
	plocaml_spi_nested \
	plocaml_gd_sd \
	plocaml_global \
	plocaml_import \
	plocaml_newline \
	plocaml_ereport \
	plocaml_error \
	plocaml_quote \
	plocaml_subtransaction \
	plocaml_drop

REGRESS_XFAIL = \
	plocaml_test \
	plocaml_call \
	plocaml_setof \
	plocaml_void \
	plocaml_composite \
	plocaml_params \
	plocaml_record \
	plocaml_trigger

EXTENSION = plocamlu
NO_INSTALL = 1
PG_CONFIG ?= /usr/lib/postgresql/16/bin/pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)

# Extension is built/installed by cargo-pgrx; PGXS only runs pg_regress.
REGRESS_OPTS = --load-extension=plocamlu
EXTRA_CLEAN = results/ regression.diffs regression.out

fmt:
	cargo fmt
	ocamlformat --inplace ml/*.ml

install:
	cargo pgrx install --no-default-features --features pg16 --pg-config $(PG_CONFIG)

regress: install
	$(MAKE) installcheck

# Full ported suite, including tests that still fail on missing features.
installcheck-all:
	$(MAKE) installcheck REGRESS="$(REGRESS) $(REGRESS_XFAIL)"
