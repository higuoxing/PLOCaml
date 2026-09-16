-- Ported from PostgreSQL src/pl/plpython/sql/plpython_transaction.sql (REL_16_STABLE).

CREATE TABLE test1 (a int, b text);


CREATE PROCEDURE transaction_test1()
LANGUAGE plocamlu
AS $$
for i = 0 to 9 do
  ignore (PL.execute (Printf.sprintf "INSERT INTO test1 (a) VALUES (%d)" i));
  if i mod 2 = 0 then PL.commit () else PL.rollback ()
done;
()
$$;

CALL transaction_test1();

SELECT * FROM test1;


TRUNCATE test1;

DO
LANGUAGE plocamlu
$$
for i = 0 to 9 do
  ignore (PL.execute (Printf.sprintf "INSERT INTO test1 (a) VALUES (%d)" i));
  if i mod 2 = 0 then PL.commit () else PL.rollback ()
done
$$;

SELECT * FROM test1;


TRUNCATE test1;

-- not allowed in a function
CREATE FUNCTION transaction_test2() RETURNS int
LANGUAGE plocamlu
AS $$
for i = 0 to 9 do
  ignore (PL.execute (Printf.sprintf "INSERT INTO test1 (a) VALUES (%d)" i));
  if i mod 2 = 0 then PL.commit () else PL.rollback ()
done;
PL.Int 1
$$;

SELECT transaction_test2();

SELECT * FROM test1;


-- also not allowed if procedure is called from a function
CREATE FUNCTION transaction_test3() RETURNS int
LANGUAGE plocamlu
AS $$
ignore (PL.execute "CALL transaction_test1()");
PL.Int 1
$$;

SELECT transaction_test3();

SELECT * FROM test1;


-- DO block inside function
CREATE FUNCTION transaction_test4() RETURNS int
LANGUAGE plocamlu
AS $$
ignore (PL.execute "DO LANGUAGE plocamlu $x$ PL.commit () $x$");
PL.Int 1
$$;

SELECT transaction_test4();


-- commit inside subtransaction (prohibited)
DO LANGUAGE plocamlu $$
PL.subtransaction (fun () -> PL.commit ())
$$;


-- commit inside cursor loop
CREATE TABLE test2 (x int);
INSERT INTO test2 VALUES (0), (1), (2), (3), (4);

TRUNCATE test1;

DO LANGUAGE plocamlu $$
let cur = PL.cursor "SELECT * FROM test2 ORDER BY x" in
let rec loop () =
  let batch = PL.fetch cur 1 in
  if batch.nrows = 0 then ()
  else (
    let x = PL.to_int_exn (List.assoc "x" batch.rows.(0)) in
    ignore (PL.execute (Printf.sprintf "INSERT INTO test1 (a) VALUES (%d)" x));
    PL.commit ();
    loop ()
  )
in
loop ()
$$;

SELECT * FROM test1;

-- check that this doesn't leak a holdable portal
SELECT * FROM pg_cursors;


-- error in cursor loop with commit
TRUNCATE test1;

DO LANGUAGE plocamlu $$
let cur = PL.cursor "SELECT * FROM test2 ORDER BY x" in
let rec loop () =
  let batch = PL.fetch cur 1 in
  if batch.nrows = 0 then ()
  else (
    let x = PL.to_int_exn (List.assoc "x" batch.rows.(0)) in
    ignore (PL.execute (Printf.sprintf "INSERT INTO test1 (a) VALUES (12/(%d-2))" x));
    PL.commit ();
    loop ()
  )
in
loop ()
$$;

SELECT * FROM test1;

SELECT * FROM pg_cursors;


-- rollback inside cursor loop
TRUNCATE test1;

DO LANGUAGE plocamlu $$
let cur = PL.cursor "SELECT * FROM test2 ORDER BY x" in
let rec loop () =
  let batch = PL.fetch cur 1 in
  if batch.nrows = 0 then ()
  else (
    let x = PL.to_int_exn (List.assoc "x" batch.rows.(0)) in
    ignore (PL.execute (Printf.sprintf "INSERT INTO test1 (a) VALUES (%d)" x));
    PL.rollback ();
    loop ()
  )
in
loop ()
$$;

SELECT * FROM test1;

SELECT * FROM pg_cursors;


-- first commit then rollback inside cursor loop
TRUNCATE test1;

DO LANGUAGE plocamlu $$
let cur = PL.cursor "SELECT * FROM test2 ORDER BY x" in
let rec loop () =
  let batch = PL.fetch cur 1 in
  if batch.nrows = 0 then ()
  else (
    let x = PL.to_int_exn (List.assoc "x" batch.rows.(0)) in
    ignore (PL.execute (Printf.sprintf "INSERT INTO test1 (a) VALUES (%d)" x));
    if x mod 2 = 0 then PL.commit () else PL.rollback ();
    loop ()
  )
in
loop ()
$$;

SELECT * FROM test1;

SELECT * FROM pg_cursors;


-- check handling of an error during COMMIT
CREATE TABLE testpk (id int PRIMARY KEY);
CREATE TABLE testfk(f1 int REFERENCES testpk DEFERRABLE INITIALLY DEFERRED);

DO LANGUAGE plocamlu $$
ignore (PL.execute "INSERT INTO testfk VALUES (0)");
PL.commit ();
PL.warning "should not get here"
$$;

SELECT * FROM testpk;
SELECT * FROM testfk;

DO LANGUAGE plocamlu $$
ignore (PL.execute "INSERT INTO testfk VALUES (0)");
(try PL.commit () with Failure e -> PL.info ("sqlstate: " ^ e));
ignore (PL.execute "INSERT INTO testpk VALUES (1)");
ignore (PL.execute "INSERT INTO testfk VALUES (1)")
$$;

SELECT * FROM testpk;
SELECT * FROM testfk;


DROP TABLE test1;
DROP TABLE test2;
