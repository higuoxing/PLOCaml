-- Ported from PostgreSQL src/pl/plpython/sql/plpython_types.sql (REL_16_STABLE).
-- Python-only pieces omitted: type() logging of Python classes, marshal,
-- Python truthiness for bool, and custom __getitem__ sequences.

--
-- Base/common types
--

CREATE FUNCTION test_type_conversion_bool(x bool) RETURNS bool AS $$
PL.info (match x with PL.Bool b -> string_of_bool b | PL.Null -> "None" | _ -> "?");
x
$$ LANGUAGE plocamlu;

SELECT * FROM test_type_conversion_bool(true);
SELECT * FROM test_type_conversion_bool(false);
SELECT * FROM test_type_conversion_bool(null);


CREATE FUNCTION test_type_conversion_char(x char) RETURNS char AS $$
PL.info (match x with PL.String s -> s | PL.Null -> "None" | _ -> "?");
x
$$ LANGUAGE plocamlu;

SELECT * FROM test_type_conversion_char('a');
SELECT * FROM test_type_conversion_char(null);


CREATE FUNCTION test_type_conversion_int2(x int2) RETURNS int2 AS $$
PL.info (match x with PL.Int i -> string_of_int i | PL.Null -> "None" | _ -> "?");
x
$$ LANGUAGE plocamlu;

SELECT * FROM test_type_conversion_int2(100::int2);
SELECT * FROM test_type_conversion_int2(-100::int2);
SELECT * FROM test_type_conversion_int2(null);


CREATE FUNCTION test_type_conversion_int4(x int4) RETURNS int4 AS $$
PL.info (match x with PL.Int i -> string_of_int i | PL.Null -> "None" | _ -> "?");
x
$$ LANGUAGE plocamlu;

SELECT * FROM test_type_conversion_int4(100);
SELECT * FROM test_type_conversion_int4(-100);
SELECT * FROM test_type_conversion_int4(null);


CREATE FUNCTION test_type_conversion_int8(x int8) RETURNS int8 AS $$
PL.info (match x with PL.Int i -> string_of_int i | PL.Null -> "None" | _ -> "?");
x
$$ LANGUAGE plocamlu;

SELECT * FROM test_type_conversion_int8(100);
SELECT * FROM test_type_conversion_int8(-100);
SELECT * FROM test_type_conversion_int8(5000000000);
SELECT * FROM test_type_conversion_int8(null);


CREATE FUNCTION test_type_conversion_numeric(x numeric) RETURNS numeric AS $$
PL.info (match x with PL.String s -> s | PL.Int i -> string_of_int i | PL.Float f -> string_of_float f | PL.Null -> "None" | _ -> "?");
x
$$ LANGUAGE plocamlu;

SELECT * FROM test_type_conversion_numeric(100);
SELECT * FROM test_type_conversion_numeric(-100);
SELECT * FROM test_type_conversion_numeric(100.0);
SELECT * FROM test_type_conversion_numeric(100.00);
SELECT * FROM test_type_conversion_numeric(5000000000.5);
SELECT * FROM test_type_conversion_numeric(1234567890.0987654321);
SELECT * FROM test_type_conversion_numeric(-1234567890.0987654321);
SELECT * FROM test_type_conversion_numeric(null);


CREATE FUNCTION test_type_conversion_float4(x float4) RETURNS float4 AS $$
PL.info (match x with PL.Float f -> string_of_float f | PL.Int i -> string_of_int i | PL.Null -> "None" | _ -> "?");
x
$$ LANGUAGE plocamlu;

SELECT * FROM test_type_conversion_float4(100);
SELECT * FROM test_type_conversion_float4(-100);
SELECT * FROM test_type_conversion_float4(5000.5);
SELECT * FROM test_type_conversion_float4(null);


CREATE FUNCTION test_type_conversion_float8(x float8) RETURNS float8 AS $$
PL.info (match x with PL.Float f -> string_of_float f | PL.Int i -> string_of_int i | PL.Null -> "None" | _ -> "?");
x
$$ LANGUAGE plocamlu;

SELECT * FROM test_type_conversion_float8(100);
SELECT * FROM test_type_conversion_float8(-100);
SELECT * FROM test_type_conversion_float8(5000000000.5);
SELECT * FROM test_type_conversion_float8(null);
SELECT * FROM test_type_conversion_float8(100100100.654321);


CREATE FUNCTION test_type_conversion_oid(x oid) RETURNS oid AS $$
PL.info (match x with PL.Int i -> string_of_int i | PL.String s -> s | PL.Null -> "None" | _ -> "?");
x
$$ LANGUAGE plocamlu;

SELECT * FROM test_type_conversion_oid(100);
SELECT * FROM test_type_conversion_oid(2147483649);
SELECT * FROM test_type_conversion_oid(null);


CREATE FUNCTION test_type_conversion_text(x text) RETURNS text AS $$
PL.info (match x with PL.String s -> s | PL.Null -> "None" | _ -> "?");
x
$$ LANGUAGE plocamlu;

SELECT * FROM test_type_conversion_text('hello world');
SELECT * FROM test_type_conversion_text(null);


CREATE FUNCTION test_type_conversion_bytea(x bytea) RETURNS bytea AS $$
PL.info (match x with PL.String s -> s | PL.Null -> "None" | _ -> "?");
x
$$ LANGUAGE plocamlu;

SELECT * FROM test_type_conversion_bytea('hello world');
SELECT * FROM test_type_conversion_bytea(E'null\\000byte');
SELECT * FROM test_type_conversion_bytea(null);


--
-- Domains
--

CREATE DOMAIN booltrue AS bool CHECK (VALUE IS TRUE OR VALUE IS NULL);

CREATE FUNCTION test_type_conversion_booltrue(x booltrue, y bool) RETURNS booltrue AS $$
y
$$ LANGUAGE plocamlu;

SELECT * FROM test_type_conversion_booltrue(true, true);
SELECT * FROM test_type_conversion_booltrue(false, true);
SELECT * FROM test_type_conversion_booltrue(true, false);


CREATE DOMAIN uint2 AS int2 CHECK (VALUE >= 0);

CREATE FUNCTION test_type_conversion_uint2(x uint2, y int) RETURNS uint2 AS $$
PL.info (match x with PL.Int i -> string_of_int i | PL.Null -> "None" | _ -> "?");
y
$$ LANGUAGE plocamlu;

SELECT * FROM test_type_conversion_uint2(100::uint2, 50);
SELECT * FROM test_type_conversion_uint2(100::uint2, -50);
SELECT * FROM test_type_conversion_uint2(null, 1);


CREATE DOMAIN nnint AS int CHECK (VALUE IS NOT NULL);

CREATE FUNCTION test_type_conversion_nnint(x nnint, y int) RETURNS nnint AS $$
y
$$ LANGUAGE plocamlu;

SELECT * FROM test_type_conversion_nnint(10, 20);
SELECT * FROM test_type_conversion_nnint(null, 20);
SELECT * FROM test_type_conversion_nnint(10, null);


--
-- Arrays
--

CREATE FUNCTION test_type_conversion_array_int4(x int4[]) RETURNS int4[] AS $$
x
$$ LANGUAGE plocamlu;

SELECT * FROM test_type_conversion_array_int4(ARRAY[0, 100]);
SELECT * FROM test_type_conversion_array_int4(ARRAY[0,-100,55]);
SELECT * FROM test_type_conversion_array_int4(ARRAY[NULL,1]);
SELECT * FROM test_type_conversion_array_int4(ARRAY[]::integer[]);
SELECT * FROM test_type_conversion_array_int4(NULL);


CREATE FUNCTION test_type_conversion_array_text(x text[]) RETURNS text[] AS $$
x
$$ LANGUAGE plocamlu;

SELECT * FROM test_type_conversion_array_text(ARRAY['foo', 'bar']);


---
--- Composite types
---

CREATE TABLE employee (
    name text,
    basesalary integer,
    bonus integer
);

INSERT INTO employee VALUES ('John', 100, 10), ('Mary', 200, 10);

CREATE OR REPLACE FUNCTION test_composite_table_input(e employee) RETURNS integer AS $$
let e = PL.to_record_exn e in
PL.Int (PL.to_int_exn (List.assoc "basesalary" e) + PL.to_int_exn (List.assoc "bonus" e))
$$ LANGUAGE plocamlu;

SELECT name, test_composite_table_input(employee.*) FROM employee;

ALTER TABLE employee DROP bonus;

SELECT name, test_composite_table_input(employee.*) FROM employee;

ALTER TABLE employee ADD bonus integer;
UPDATE employee SET bonus = 10;

SELECT name, test_composite_table_input(employee.*) FROM employee;

CREATE TYPE named_pair AS (
    i integer,
    j integer
);

CREATE OR REPLACE FUNCTION test_composite_type_input(p named_pair) RETURNS integer AS $$
let p = PL.to_record_exn p in
let sum = List.fold_left (fun acc (_, v) -> acc + PL.to_int ~default:0 v) 0 p in
PL.Int sum
$$ LANGUAGE plocamlu;

SELECT test_composite_type_input(row(1, 2));

ALTER TYPE named_pair RENAME TO named_pair_2;

SELECT test_composite_type_input(row(1, 2));


--
-- Prepared statements
--

CREATE OR REPLACE FUNCTION test_prep_bool_output() RETURNS bool
LANGUAGE plocamlu
AS $$
let plan = PL.prepare "SELECT $1 = 1 AS val" [|"int"|] in
let rv = PL.execute_plan plan [| PL.Int 0 |] in
PL.info (match List.assoc "val" rv.rows.(0) with PL.Bool b -> string_of_bool b | _ -> "?");
List.assoc "val" rv.rows.(0)
$$;

SELECT test_prep_bool_output(); -- false
