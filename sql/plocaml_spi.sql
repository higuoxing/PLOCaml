-- Ported from PostgreSQL src/pl/plpython/sql/plpython_spi.sql (REL_16_STABLE).
--
-- nested calls
--

CREATE FUNCTION nested_call_one(a text) RETURNS text
	AS $$
let a = PL.to_string_exn a in
let q = Printf.sprintf "SELECT nested_call_two('%s')" a in
let r = PL.execute q in
(match r.rows.(0) with (_, v) :: _ -> v | [] -> PL.Null)
$$ LANGUAGE plocamlu;

CREATE FUNCTION nested_call_two(a text) RETURNS text
	AS $$
let a = PL.to_string_exn a in
let q = Printf.sprintf "SELECT nested_call_three('%s')" a in
let r = PL.execute q in
(match r.rows.(0) with (_, v) :: _ -> v | [] -> PL.Null)
$$ LANGUAGE plocamlu;

CREATE FUNCTION nested_call_three(a text) RETURNS text
	AS $$
a
$$ LANGUAGE plocamlu;

-- some spi stuff

CREATE FUNCTION spi_prepared_plan_test_one(a text) RETURNS text
	AS $$
if not (Hashtbl.mem sd "myplan") then
  PL.set sd "myplan" (PL.prepare "SELECT count(*) FROM users WHERE lname = $1" [|"text"|]);
try
  let rv = PL.execute_plan (PL.get sd "myplan") [| a |] in
  let count = match List.assoc "count" rv.rows.(0) with
    | PL.Int n -> string_of_int n
    | PL.String s -> s
    | _ -> "?"
  in
  PL.String ("there are " ^ count ^ " " ^ PL.to_string_exn a ^ "s")
with Failure ex ->
  PL.error ex;
  PL.Null
$$ LANGUAGE plocamlu;

CREATE FUNCTION spi_prepared_plan_test_two(a text) RETURNS text
	AS $$
if not (Hashtbl.mem sd "myplan") then
  PL.set sd "myplan" (PL.prepare "SELECT count(*) FROM users WHERE lname = $1" [|"text"|]);
try
  let rv = PL.execute_plan (PL.get sd "myplan") [| a |] in
  let count = match List.assoc "count" rv.rows.(0) with
    | PL.Int n -> string_of_int n
    | PL.String s -> s
    | _ -> "?"
  in
  PL.String ("there are " ^ count ^ " " ^ PL.to_string_exn a ^ "s")
with Failure ex ->
  PL.error ex;
  PL.Null
$$ LANGUAGE plocamlu;

CREATE FUNCTION spi_prepared_plan_test_nested(a text) RETURNS text
	AS $$
if not (Hashtbl.mem sd "myplan") then (
  let q = Printf.sprintf "SELECT spi_prepared_plan_test_one('%s') as count" (PL.to_string_exn a) in
  PL.set sd "myplan" (PL.prepare q [||])
);
try
  let rv = PL.execute_plan (PL.get sd "myplan") [||] in
  if Array.length rv.rows > 0 then List.assoc "count" rv.rows.(0)
  else PL.Null
with Failure ex ->
  PL.error ex;
  PL.Null
$$ LANGUAGE plocamlu;

CREATE FUNCTION join_sequences(s sequences) RETURNS text
	AS $$
let s = PL.to_record_exn s in
let multipart = match List.assoc "multipart" s with PL.Bool b -> b | _ -> false in
let seq0 = PL.to_string_exn (List.assoc "sequence" s) in
if not multipart then PL.String seq0
else
  let pid = match List.assoc "pid" s with PL.Int n -> string_of_int n | PL.String t -> t | _ -> "" in
  let q = "SELECT sequence FROM xsequences WHERE pid = '" ^ pid ^ "'" in
  let rv = PL.execute q in
  let seq = ref seq0 in
  Array.iter (fun r ->
    seq := !seq ^ PL.to_string_exn (List.assoc "sequence" r)
  ) rv.rows;
  PL.String !seq
$$ LANGUAGE plocamlu;

CREATE FUNCTION spi_recursive_sum(a int) RETURNS int
	AS $$
let a = PL.to_int_exn a in
let r =
  if a > 1 then
    match List.assoc "a" (PL.execute (Printf.sprintf "SELECT spi_recursive_sum(%d) as a" (a - 1))).rows.(0) with
    | PL.Int n -> n
    | _ -> 0
  else 0
in
PL.Int (a + r)
$$ LANGUAGE plocamlu;

--
-- spi and nested calls
--
select nested_call_one('pass this along');
select spi_prepared_plan_test_one('doe');
select spi_prepared_plan_test_two('smith');
select spi_prepared_plan_test_nested('smith');

SELECT join_sequences(sequences) FROM sequences;
SELECT join_sequences(sequences) FROM sequences
	WHERE join_sequences(sequences) ~* '^A';
SELECT join_sequences(sequences) FROM sequences
	WHERE join_sequences(sequences) ~* '^B';

SELECT spi_recursive_sum(10);

--
-- plan and result objects
--

CREATE FUNCTION result_metadata_test(cmd text) RETURNS int
AS $$
(* official inspects plan.status / colnames / coltypes / coltypmods;
   PL/OCaml currently exposes nrows / status / rows only. *)
let cmd = PL.to_string_exn cmd in
let plan = PL.prepare cmd [||] in
ignore plan;
let result = PL.execute cmd in
if result.status > 0 then (
  PL.info (Printf.sprintf "nrows=%d status=%d" result.nrows result.status);
  PL.Int result.nrows
) else PL.Null
$$ LANGUAGE plocamlu;

SELECT result_metadata_test($$SELECT 1 AS foo, '11'::text AS bar UNION SELECT 2, '22'$$);
SELECT result_metadata_test($$CREATE TEMPORARY TABLE foo1 (a int, b text)$$);

CREATE FUNCTION result_nrows_test(cmd text) RETURNS int
AS $$
let result = PL.execute (PL.to_string_exn cmd) in
PL.Int result.nrows
$$ LANGUAGE plocamlu;

SELECT result_nrows_test($$SELECT 1$$);
SELECT result_nrows_test($$CREATE TEMPORARY TABLE foo2 (a int, b text)$$);
SELECT result_nrows_test($$INSERT INTO foo2 VALUES (1, 'one'), (2, 'two')$$);
SELECT result_nrows_test($$UPDATE foo2 SET b = '' WHERE a = 2$$);

CREATE FUNCTION result_len_test(cmd text) RETURNS int
AS $$
let result = PL.execute (PL.to_string_exn cmd) in
PL.Int (Array.length result.rows)
$$ LANGUAGE plocamlu;

SELECT result_len_test($$SELECT 1$$);
SELECT result_len_test($$CREATE TEMPORARY TABLE foo3 (a int, b text)$$);
SELECT result_len_test($$INSERT INTO foo3 VALUES (1, 'one'), (2, 'two')$$);
SELECT result_len_test($$UPDATE foo3 SET b= '' WHERE a = 2$$);

CREATE FUNCTION result_subscript_test() RETURNS void
AS $$
let result = PL.execute
  "SELECT 1 AS c UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4" in
let get i = PL.to_int_exn (List.assoc "c" result.rows.(i)) in
PL.info (string_of_int (get 1));
PL.info (string_of_int (get (Array.length result.rows - 1)));
PL.info (Printf.sprintf "[%d; %d]" (get 1) (get 2));
PL.info (Printf.sprintf "[%d; %d]" (get 0) (get 2));
PL.Null
$$ LANGUAGE plocamlu;

SELECT result_subscript_test();

CREATE FUNCTION result_empty_test() RETURNS void
AS $$
let result = PL.execute "select 1 where false" in
PL.info (Printf.sprintf "nrows=%d" result.nrows);
PL.Null
$$ LANGUAGE plocamlu;

SELECT result_empty_test();

CREATE FUNCTION result_str_test(cmd text) RETURNS text
AS $$
let cmd = PL.to_string_exn cmd in
let _plan = PL.prepare cmd [||] in
let result = PL.execute cmd in
PL.String (Printf.sprintf "<spi_result nrows=%d status=%d>" result.nrows result.status)
$$ LANGUAGE plocamlu;

SELECT result_str_test($$SELECT 1 AS foo UNION SELECT 2$$);
SELECT result_str_test($$CREATE TEMPORARY TABLE foo1 (a int, b text)$$);

-- cursor objects

CREATE FUNCTION simple_cursor_test() RETURNS int AS $$
let res = PL.cursor "select fname, lname from users" in
let rec loop n =
  let batch = PL.fetch res 1 in
  if batch.nrows = 0 then n
  else
    let lname = match List.assoc "lname" batch.rows.(0) with PL.String s -> s | _ -> "" in
    loop (if lname = "doe" then n + 1 else n)
in
let n = loop 0 in
PL.close res;
PL.Int n
$$ LANGUAGE plocamlu;

CREATE FUNCTION double_cursor_close() RETURNS int AS $$
let res = PL.cursor "select fname, lname from users" in
PL.close res;
PL.close res;
PL.Null
$$ LANGUAGE plocamlu;

CREATE FUNCTION cursor_fetch() RETURNS int AS $$
let res = PL.cursor "select fname, lname from users" in
if (PL.fetch res 3).nrows <> 3 then failwith "expected 3";
if (PL.fetch res 3).nrows <> 1 then failwith "expected 1";
if (PL.fetch res 3).nrows <> 0 then failwith "expected 0";
if (PL.fetch res 3).nrows <> 0 then failwith "expected 0";
PL.Null
$$ LANGUAGE plocamlu;

CREATE FUNCTION cursor_mix_next_and_fetch() RETURNS int AS $$
let res = PL.cursor "select fname, lname from users order by fname" in
if (PL.fetch res 2).nrows <> 2 then failwith "expected 2";
let item = PL.fetch res 1 in
(match List.assoc "fname" item.rows.(0) with
 | PL.String "rick" -> ()
 | _ -> failwith "expected rick");
if (PL.fetch res 2).nrows <> 1 then failwith "expected 1";
PL.Null
$$ LANGUAGE plocamlu;

CREATE FUNCTION fetch_after_close() RETURNS int AS $$
let res = PL.cursor "select fname, lname from users" in
PL.close res;
try
  ignore (PL.fetch res 1);
  failwith "ValueError not raised"
with Failure _ -> PL.Null
$$ LANGUAGE plocamlu;

CREATE FUNCTION next_after_close() RETURNS int AS $$
let res = PL.cursor "select fname, lname from users" in
PL.close res;
try
  ignore (PL.fetch res 1);
  failwith "ValueError not raised"
with Failure _ -> PL.Null
$$ LANGUAGE plocamlu;

CREATE FUNCTION cursor_fetch_next_empty() RETURNS int AS $$
let res = PL.cursor "select fname, lname from users where false" in
if (PL.fetch res 1).nrows <> 0 then failwith "expected empty";
PL.Null
$$ LANGUAGE plocamlu;

CREATE FUNCTION cursor_plan() RETURNS SETOF text AS $$
let plan = PL.prepare
  "select fname, lname from users where fname like $1 || '%' order by fname"
  [|"text"|] in
let acc = ref [] in
let rec drain cur =
  let batch = PL.fetch cur 1 in
  if batch.nrows = 0 then ()
  else (
    acc := List.assoc "fname" batch.rows.(0) :: !acc;
    drain cur
  )
in
drain (PL.cursor_plan plan [| PL.String "w" |]);
drain (PL.cursor_plan plan [| PL.String "j" |]);
PL.Array (Array.of_list (List.rev !acc))
$$ LANGUAGE plocamlu;

CREATE FUNCTION cursor_plan_wrong_args() RETURNS SETOF text AS $$
let plan = PL.prepare "select fname, lname from users where fname like $1 || '%'" [|"text"|] in
ignore (PL.cursor_plan plan [| PL.String "a"; PL.String "b" |]);
PL.Null
$$ LANGUAGE plocamlu;

CREATE TYPE test_composite_type AS (
  a1 int,
  a2 varchar
);

CREATE OR REPLACE FUNCTION plan_composite_args() RETURNS test_composite_type AS $$
let plan = PL.prepare "select $1 as c1" [|"test_composite_type"|] in
let res = PL.execute_plan plan [| PL.Record [("a1", PL.Int 3); ("a2", PL.String "label")] |] in
List.assoc "c1" res.rows.(0)
$$ LANGUAGE plocamlu;

SELECT simple_cursor_test();
SELECT double_cursor_close();
SELECT cursor_fetch();
SELECT cursor_mix_next_and_fetch();
SELECT fetch_after_close();
SELECT next_after_close();
SELECT cursor_fetch_next_empty();
SELECT cursor_plan();
SELECT cursor_plan_wrong_args();
SELECT plan_composite_args();

-- Official also tests Python sequences whose __getitem__ raises.
-- OCaml has no analog; omitted.
