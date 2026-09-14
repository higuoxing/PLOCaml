-- Ported from PostgreSQL src/pl/plpython/sql/plpython_do.sql (REL_16_STABLE).

DO $$ PL.notice "This is plocamlu." $$ LANGUAGE plocamlu;

DO $$ failwith "error test" $$ LANGUAGE plocamlu;
