-- Ported from PostgreSQL src/pl/plpython/sql/plpython_setof.sql (REL_16_STABLE).
--
-- Test returning SETOF
--

CREATE FUNCTION test_setof_error() RETURNS SETOF text AS $$
PL.Int 37
$$ LANGUAGE plocamlu;

SELECT test_setof_error();


CREATE FUNCTION test_setof_as_list(count integer, content text) RETURNS SETOF text AS $$
let count = PL.to_int ~default:0 count in
let content = match content with PL.Null -> PL.Null | v -> v in
PL.Array (Array.make count content)
$$ LANGUAGE plocamlu;

CREATE FUNCTION test_setof_as_tuple(count integer, content text) RETURNS SETOF text AS $$
let count = PL.to_int ~default:0 count in
let content = match content with PL.Null -> PL.Null | v -> v in
PL.Array (Array.make count content)
$$ LANGUAGE plocamlu;

CREATE FUNCTION test_setof_as_iterator(count integer, content text) RETURNS SETOF text AS $$
let count = PL.to_int ~default:0 count in
let content = match content with PL.Null -> PL.Null | v -> v in
PL.Array (Array.make count content)
$$ LANGUAGE plocamlu;

CREATE FUNCTION test_setof_spi_in_iterator() RETURNS SETOF text AS
$$
  let words = [|"Hello"; "Brave"; "New"; "World"|] in
  let rec loop i acc =
    if i >= Array.length words then List.rev acc
    else (
      ignore (PL.execute "select 1");
      let acc = PL.String words.(i) :: acc in
      ignore (PL.execute "select 2");
      loop (i + 1) acc
    )
  in
  PL.Array (Array.of_list (loop 0 []))
$$
LANGUAGE plocamlu;


-- Test set returning functions
SELECT test_setof_as_list(0, 'list');
SELECT test_setof_as_list(1, 'list');
SELECT test_setof_as_list(2, 'list');
SELECT test_setof_as_list(2, null);

SELECT test_setof_as_tuple(0, 'tuple');
SELECT test_setof_as_tuple(1, 'tuple');
SELECT test_setof_as_tuple(2, 'tuple');
SELECT test_setof_as_tuple(2, null);

SELECT test_setof_as_iterator(0, 'list');
SELECT test_setof_as_iterator(1, 'list');
SELECT test_setof_as_iterator(2, 'list');
SELECT test_setof_as_iterator(2, null);

SELECT test_setof_spi_in_iterator();

-- set-returning function that modifies its parameters
CREATE OR REPLACE FUNCTION ugly(x int, lim int) RETURNS SETOF int AS $$
let rec loop x lim acc =
  if x > lim then List.rev acc
  else loop (x + 1) lim (PL.Int x :: acc)
in
PL.Array (Array.of_list (loop (PL.to_int_exn x) (PL.to_int_exn lim) []))
$$ LANGUAGE plocamlu;

SELECT ugly(1, 5);

-- interleaved execution of such a function
SELECT ugly(1,3), ugly(7,8);

-- returns set of named-composite-type tuples
CREATE OR REPLACE FUNCTION get_user_records()
RETURNS SETOF users
AS $$
    let rv = PL.execute "SELECT * FROM users ORDER BY username" in
    PL.Array (Array.map (fun row -> PL.Record row) rv.rows)
$$ LANGUAGE plocamlu;

SELECT get_user_records();
SELECT * FROM get_user_records();

-- same, but returning set of RECORD
CREATE OR REPLACE FUNCTION get_user_records2()
RETURNS TABLE(fname text, lname text, username text, userid int)
AS $$
    let rv = PL.execute "SELECT * FROM users ORDER BY username" in
    PL.Array (Array.map (fun row -> PL.Record row) rv.rows)
$$ LANGUAGE plocamlu;

SELECT get_user_records2();
SELECT * FROM get_user_records2();
