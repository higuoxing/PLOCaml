-- Ported from PostgreSQL src/pl/plpython/sql/plpython_record.sql (REL_16_STABLE).
--
-- Test returning tuples
--

CREATE TABLE table_record (
	first text,
	second int4
	) ;

CREATE TYPE type_record AS (
	first text,
	second int4
	) ;


CREATE FUNCTION test_table_record_as(typ text, first text, second integer, retnull boolean) RETURNS table_record AS $$
if PL.to_bool ~default:false retnull then PL.Null
else
  let first = match first with PL.Null -> PL.Null | v -> v in
  let second = match second with PL.Null -> PL.Null | v -> v in
  match PL.to_string_exn typ with
  | "dict" | "obj" ->
      PL.Record [("first", first); ("second", second); ("additionalfield", PL.String "must not cause trouble")]
  | "tuple" | "list" ->
      PL.Array [| first; second |]
  | _ -> failwith "unrecognized typ"
$$ LANGUAGE plocamlu;

CREATE FUNCTION test_type_record_as(typ text, first text, second integer, retnull boolean) RETURNS type_record AS $$
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
      let f = match first with PL.String s -> s | PL.Null -> "" | _ -> "?" in
      let s = match second with PL.Int i -> string_of_int i | PL.Null -> "None" | _ -> "?" in
      PL.String (Printf.sprintf "('%s',%s)" f s)
  | _ -> failwith "unrecognized typ"
$$ LANGUAGE plocamlu;

CREATE FUNCTION test_in_out_params(first in text, second out text) AS $$
PL.String (PL.to_string_exn first ^ "_in_to_out")
$$ LANGUAGE plocamlu;

CREATE FUNCTION test_in_out_params_multi(first in text,
                                         second out text, third out text) AS $$
let first = PL.to_string_exn first in
PL.Array [| PL.String (first ^ "_record_in_to_out_1");
            PL.String (first ^ "_record_in_to_out_2") |]
$$ LANGUAGE plocamlu;

CREATE FUNCTION test_inout_params(first inout text) AS $$
PL.String (PL.to_string_exn first ^ "_inout")
$$ LANGUAGE plocamlu;


-- Test tuple returning functions
SELECT * FROM test_table_record_as('dict', null, null, false);
SELECT * FROM test_table_record_as('dict', 'one', null, false);
SELECT * FROM test_table_record_as('dict', null, 2, false);
SELECT * FROM test_table_record_as('dict', 'three', 3, false);
SELECT * FROM test_table_record_as('dict', null, null, true);

SELECT * FROM test_table_record_as('tuple', null, null, false);
SELECT * FROM test_table_record_as('tuple', 'one', null, false);
SELECT * FROM test_table_record_as('tuple', null, 2, false);
SELECT * FROM test_table_record_as('tuple', 'three', 3, false);
SELECT * FROM test_table_record_as('tuple', null, null, true);

SELECT * FROM test_table_record_as('list', null, null, false);
SELECT * FROM test_table_record_as('list', 'one', null, false);
SELECT * FROM test_table_record_as('list', null, 2, false);
SELECT * FROM test_table_record_as('list', 'three', 3, false);
SELECT * FROM test_table_record_as('list', null, null, true);

SELECT * FROM test_table_record_as('obj', null, null, false);
SELECT * FROM test_table_record_as('obj', 'one', null, false);
SELECT * FROM test_table_record_as('obj', null, 2, false);
SELECT * FROM test_table_record_as('obj', 'three', 3, false);
SELECT * FROM test_table_record_as('obj', null, null, true);

SELECT * FROM test_type_record_as('dict', null, null, false);
SELECT * FROM test_type_record_as('dict', 'one', null, false);
SELECT * FROM test_type_record_as('dict', null, 2, false);
SELECT * FROM test_type_record_as('dict', 'three', 3, false);
SELECT * FROM test_type_record_as('dict', null, null, true);

SELECT * FROM test_type_record_as('tuple', null, null, false);
SELECT * FROM test_type_record_as('tuple', 'one', null, false);
SELECT * FROM test_type_record_as('tuple', null, 2, false);
SELECT * FROM test_type_record_as('tuple', 'three', 3, false);
SELECT * FROM test_type_record_as('tuple', null, null, true);

SELECT * FROM test_type_record_as('list', null, null, false);
SELECT * FROM test_type_record_as('list', 'one', null, false);
SELECT * FROM test_type_record_as('list', null, 2, false);
SELECT * FROM test_type_record_as('list', 'three', 3, false);
SELECT * FROM test_type_record_as('list', null, null, true);

SELECT * FROM test_type_record_as('obj', null, null, false);
SELECT * FROM test_type_record_as('obj', 'one', null, false);
SELECT * FROM test_type_record_as('obj', null, 2, false);
SELECT * FROM test_type_record_as('obj', 'three', 3, false);
SELECT * FROM test_type_record_as('obj', null, null, true);

SELECT * FROM test_type_record_as('str', 'one', 1, false);

SELECT * FROM test_in_out_params('test_in');
SELECT * FROM test_in_out_params_multi('test_in');
SELECT * FROM test_inout_params('test_in');

-- try changing the return types and call functions again

ALTER TABLE table_record DROP COLUMN first;
ALTER TABLE table_record DROP COLUMN second;
ALTER TABLE table_record ADD COLUMN first text;
ALTER TABLE table_record ADD COLUMN second int4;

SELECT * FROM test_table_record_as('obj', 'one', 1, false);

ALTER TYPE type_record DROP ATTRIBUTE first;
ALTER TYPE type_record DROP ATTRIBUTE second;
ALTER TYPE type_record ADD ATTRIBUTE first text;
ALTER TYPE type_record ADD ATTRIBUTE second int4;

SELECT * FROM test_type_record_as('obj', 'one', 1, false);

-- errors cases

CREATE FUNCTION test_type_record_error1() RETURNS type_record AS $$
    PL.Record [("first", PL.String "first")]
$$ LANGUAGE plocamlu;

SELECT * FROM test_type_record_error1();


CREATE FUNCTION test_type_record_error2() RETURNS type_record AS $$
    PL.Array [| PL.String "first" |]
$$ LANGUAGE plocamlu;

SELECT * FROM test_type_record_error2();


CREATE FUNCTION test_type_record_error3() RETURNS type_record AS $$
    PL.Record [("first", PL.String "first")]
$$ LANGUAGE plocamlu;

SELECT * FROM test_type_record_error3();

CREATE FUNCTION test_type_record_error4() RETURNS type_record AS $$
    PL.String "foo"
$$ LANGUAGE plocamlu;

SELECT * FROM test_type_record_error4();
