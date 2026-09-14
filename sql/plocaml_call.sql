-- Ported from PostgreSQL src/pl/plpython/sql/plpython_call.sql (REL_16_STABLE).
--
-- Tests for procedures / CALL syntax
--

CREATE PROCEDURE test_proc1()
LANGUAGE plocamlu
AS $$
PL.Null
$$;

CALL test_proc1();


-- error: can't return non-None
CREATE PROCEDURE test_proc2()
LANGUAGE plocamlu
AS $$
PL.Int 5
$$;

CALL test_proc2();


CREATE TABLE test1 (a int);

CREATE PROCEDURE test_proc3(x int)
LANGUAGE plocamlu
AS $$
let x = PL.to_int_exn x in
ignore (PL.execute (Printf.sprintf "INSERT INTO test1 VALUES (%d)" x));
PL.Null
$$;

CALL test_proc3(55);

SELECT * FROM test1;


-- output arguments

CREATE PROCEDURE test_proc5(INOUT a text)
LANGUAGE plocamlu
AS $$
let a = PL.to_string_exn a in
PL.Array [| PL.String (a ^ "+" ^ a) |]
$$;

CALL test_proc5('abc');


CREATE PROCEDURE test_proc6(a int, INOUT b int, INOUT c int)
LANGUAGE plocamlu
AS $$
let a = PL.to_int_exn a in
let b = PL.to_int_exn b in
let c = PL.to_int_exn c in
PL.Array [| PL.Int (b * a); PL.Int (c * a) |]
$$;

CALL test_proc6(2, 3, 4);


-- OUT parameters

CREATE PROCEDURE test_proc9(IN a int, OUT b int)
LANGUAGE plocamlu
AS $$
let a = PL.to_int_exn a in
PL.notice (Printf.sprintf "a: %d" a);
PL.Array [| PL.Int (a * 2) |]
$$;

DO $$
DECLARE _a int; _b int;
BEGIN
  _a := 10; _b := 30;
  CALL test_proc9(_a, _b);
  RAISE NOTICE '_a: %, _b: %', _a, _b;
END
$$;


DROP PROCEDURE test_proc1;
DROP PROCEDURE test_proc2;
DROP PROCEDURE test_proc3;

DROP TABLE test1;
