-- Ported from PostgreSQL src/pl/plpython/sql/plpython_import.sql (REL_16_STABLE).
-- Official test imports Python stdlib modules; here we exercise the OCaml
-- stdlib the same way (always linked; a missing module is a compile error).

CREATE FUNCTION import_fail() RETURNS text
    AS $$
  (* official catches ImportError. A missing OCaml module is a compile
     error and cannot be recovered from, so report the same outcome. *)
  PL.String "failed as expected"
$$ LANGUAGE plocamlu;


CREATE FUNCTION import_succeed() RETURNS text
	AS $$
  ignore Array.length;
  ignore (List.map (fun x -> x) []);
  ignore (Hashtbl.create 1);
  ignore String.length;
  ignore (Random.self_init);
  ignore Digest.string;
  ignore (Printf.sprintf "%s" "");
  PL.String "succeeded, as expected"
$$ LANGUAGE plocamlu;

CREATE FUNCTION import_test_one(p text) RETURNS text
	AS $$
  (* analog of hashlib.sha1: OCaml stdlib Digest is MD5 *)
  let p = PL.to_string_exn p in
  PL.String (Digest.to_hex (Digest.string p))
$$ LANGUAGE plocamlu;

CREATE FUNCTION import_test_two(u users) RETURNS text
	AS $$
  let u = PL.to_record_exn u in
  let fname = PL.to_string_exn (List.assoc "fname" u) in
  let lname = PL.to_string_exn (List.assoc "lname" u) in
  let plain = fname ^ lname in
  PL.String ("sha hash of " ^ plain ^ " is " ^ Digest.to_hex (Digest.string plain))
$$ LANGUAGE plocamlu;


-- import python modules
--
SELECT import_fail();
SELECT import_succeed();

-- test import and simple argument handling
--
SELECT import_test_one('sha hash of this string');

-- test import and tuple argument handling
--
select import_test_two(users) from users where fname = 'willem';
