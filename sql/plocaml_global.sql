-- Ported from PostgreSQL src/pl/plpython/sql/plpython_global.sql (REL_16_STABLE).
--
-- check static and global data (SD and GD)
--

CREATE FUNCTION global_test_one() RETURNS text
    AS $$
if not (Hashtbl.mem sd "global_test") then
  PL.set sd "global_test" "set by global_test_one";
if not (Hashtbl.mem gd "global_test") then
  PL.set gd "global_test" "set by global_test_one";
PL.String ("SD: " ^ PL.get sd "global_test" ^ ", GD: " ^ PL.get gd "global_test")
$$ LANGUAGE plocamlu;

CREATE FUNCTION global_test_two() RETURNS text
    AS $$
if not (Hashtbl.mem sd "global_test") then
  PL.set sd "global_test" "set by global_test_two";
if not (Hashtbl.mem gd "global_test") then
  PL.set gd "global_test" "set by global_test_two";
PL.String ("SD: " ^ PL.get sd "global_test" ^ ", GD: " ^ PL.get gd "global_test")
$$ LANGUAGE plocamlu;


CREATE FUNCTION static_test() RETURNS int4
    AS $$
let n = match PL.get_opt sd "call" with Some c -> c + 1 | None -> 1 in
PL.set sd "call" n;
PL.Int n
$$ LANGUAGE plocamlu;


SELECT static_test();
SELECT static_test();
SELECT global_test_one();
SELECT global_test_two();
