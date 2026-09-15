-- Ported from PostgreSQL src/pl/plpython/sql/plpython_composite.sql (REL_16_STABLE).

CREATE FUNCTION multiout_simple(OUT i integer, OUT j integer) AS $$
PL.Array [| PL.Int 1; PL.Int 2 |]
$$ LANGUAGE plocamlu;

SELECT multiout_simple();
SELECT * FROM multiout_simple();
SELECT i, j + 2 FROM multiout_simple();
SELECT (multiout_simple()).j + 3;

CREATE FUNCTION multiout_simple_setof(n integer = 1, OUT integer, OUT integer) RETURNS SETOF record AS $$
let n = PL.to_int ~default:1 n in
PL.Array (Array.make n (PL.Array [| PL.Int 1; PL.Int 2 |]))
$$ LANGUAGE plocamlu;

SELECT multiout_simple_setof();
SELECT * FROM multiout_simple_setof();
SELECT * FROM multiout_simple_setof(3);

CREATE FUNCTION multiout_record_as(typ text,
                                   first text, OUT first text,
                                   second integer, OUT second integer,
                                   retnull boolean) RETURNS record AS $$
if PL.to_bool ~default:false retnull then PL.Null
else
  let first = match first with PL.Null -> PL.Null | v -> v in
  let second = match second with PL.Null -> PL.Null | v -> v in
  match PL.to_string_exn typ with
  | "dict" | "obj" ->
      PL.Record [("first", first); ("second", second); ("additionalfield", PL.String "must not cause trouble")]
  | "tuple" | "list" ->
      PL.Array [| first; second |]
  | "str" ->
      let f = match first with PL.String s -> s | _ -> "" in
      let s = match second with PL.Int i -> string_of_int i | _ -> "None" in
      PL.String (Printf.sprintf "('%s',%s)" f s)
  | _ -> failwith "unrecognized typ"
$$ LANGUAGE plocamlu;

SELECT * FROM multiout_record_as('dict', 'foo', 1, 'f');
SELECT multiout_record_as('dict', 'foo', 1, 'f');

SELECT * FROM multiout_record_as('dict', null, null, false);
SELECT * FROM multiout_record_as('dict', 'one', null, false);
SELECT * FROM multiout_record_as('dict', null, 2, false);
SELECT * FROM multiout_record_as('dict', 'three', 3, false);
SELECT * FROM multiout_record_as('dict', null, null, true);

SELECT * FROM multiout_record_as('tuple', null, null, false);
SELECT * FROM multiout_record_as('tuple', 'one', null, false);
SELECT * FROM multiout_record_as('tuple', null, 2, false);
SELECT * FROM multiout_record_as('tuple', 'three', 3, false);
SELECT * FROM multiout_record_as('tuple', null, null, true);

SELECT * FROM multiout_record_as('list', null, null, false);
SELECT * FROM multiout_record_as('list', 'one', null, false);
SELECT * FROM multiout_record_as('list', null, 2, false);
SELECT * FROM multiout_record_as('list', 'three', 3, false);
SELECT * FROM multiout_record_as('list', null, null, true);

SELECT * FROM multiout_record_as('obj', null, null, false);
SELECT * FROM multiout_record_as('obj', 'one', null, false);
SELECT * FROM multiout_record_as('obj', null, 2, false);
SELECT * FROM multiout_record_as('obj', 'three', 3, false);
SELECT * FROM multiout_record_as('obj', null, null, true);

SELECT * FROM multiout_record_as('str', 'one', 1, false);
SELECT * FROM multiout_record_as('str', 'one', 2, false);

CREATE FUNCTION multiout_setof(n integer,
                               OUT power_of_2 integer,
                               OUT length integer) RETURNS SETOF record AS $$
let n = PL.to_int_exn n in
let rec loop i acc =
  if i >= n then List.rev acc
  else
    let power = 1 lsl i in
    let length = PL.to_int_exn (List.assoc "length"
      (PL.execute (Printf.sprintf "select length('%d')" power)).rows.(0)) in
    loop (i + 1) (PL.Record [("power_of_2", PL.Int power); ("length", PL.Int length)] :: acc)
in
PL.Array (Array.of_list (loop 0 []))
$$ LANGUAGE plocamlu;

SELECT * FROM multiout_setof(3);
SELECT multiout_setof(5);

CREATE FUNCTION multiout_return_table() RETURNS TABLE (x integer, y text) AS $$
PL.Array [|
  PL.Record [("x", PL.Int 4); ("y", PL.String "four")];
  PL.Record [("x", PL.Int 7); ("y", PL.String "seven")];
  PL.Record [("x", PL.Int 0); ("y", PL.String "zero")]
|]
$$ LANGUAGE plocamlu;

SELECT * FROM multiout_return_table();

CREATE FUNCTION return_record(t text) RETURNS record AS $$
PL.Record [("t", t); ("val", PL.Int 10)]
$$ LANGUAGE plocamlu;

SELECT * FROM return_record('abc') AS r(t text, val integer);
SELECT * FROM return_record('abc') AS r(t text, val bigint);
SELECT * FROM return_record('abc') AS r(t text, val integer);
SELECT * FROM return_record('abc') AS r(t varchar(30), val integer);
SELECT * FROM return_record('abc') AS r(t varchar(100), val integer);
SELECT * FROM return_record('999') AS r(val text, t integer);
