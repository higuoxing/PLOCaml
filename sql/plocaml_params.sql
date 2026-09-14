-- Ported from PostgreSQL src/pl/plpython/sql/plpython_params.sql (REL_16_STABLE).
--
-- Test named and nameless parameters
--

CREATE FUNCTION test_param_names0(integer, integer) RETURNS int AS $$
PL.Int (PL.to_int_exn args.(0) + PL.to_int_exn args.(1))
$$ LANGUAGE plocamlu;

CREATE FUNCTION test_param_names1(a0 integer, a1 text) RETURNS boolean AS $$
if a0 <> args.(0) then failwith "a0 != args.(0)";
if a1 <> args.(1) then failwith "a1 != args.(1)";
PL.Bool true
$$ LANGUAGE plocamlu;

CREATE FUNCTION test_param_names2(u users) RETURNS text AS $$
if u <> args.(0) then failwith "u != args.(0)";
(match u with
 | PL.Null -> PL.String "None"
 | PL.Record fields ->
     let keys = List.sort (fun (k1, _) (k2, _) -> String.compare k1 k2) fields in
     let fmt = function
       | PL.String s -> Printf.sprintf "%S" s
       | PL.Int i -> string_of_int i
       | PL.Null -> "None"
       | PL.Bool b -> string_of_bool b
       | _ -> "?"
     in
     let body = String.concat ", " (List.map (fun (k, v) ->
       Printf.sprintf "%S: %s" k (fmt v)) keys) in
     PL.String ("{" ^ body ^ "}")
 | _ -> PL.String "?")
$$ LANGUAGE plocamlu;

-- use deliberately wrong parameter names
CREATE FUNCTION test_param_names3(a0 integer) RETURNS boolean AS $$
(* official: `assert a1 == args[0]` raises NameError. An unbound
   identifier is a compile error in OCaml, so we analogize with a
   missing named binding. *)
try
  ignore (PL.get sd "a1");
  PL.Bool false
with Failure msg ->
  if not (String.contains msg 'a') then failwith msg;
  PL.Bool true
$$ LANGUAGE plocamlu;


SELECT test_param_names0(2,7);
SELECT test_param_names1(1,'text');
SELECT test_param_names2(users) from users;
SELECT test_param_names2(NULL);
SELECT test_param_names3(1);
