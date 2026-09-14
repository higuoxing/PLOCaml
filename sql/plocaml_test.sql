-- Ported from PostgreSQL src/pl/plpython/sql/plpython_test.sql (REL_16_STABLE).
-- first some tests of basic functionality

-- really stupid function just to get the module loaded
CREATE FUNCTION stupid() RETURNS text AS $$
  PL.String "zarkon"
$$ LANGUAGE plocamlu;

select stupid();

-- check versioning / another simple function
CREATE FUNCTION stupidn() RETURNS text AS $$
  PL.String "zarkon"
$$ LANGUAGE plocamlu;

select stupidn();

-- test multiple arguments and odd characters in function name
CREATE FUNCTION "Argument test #1"(u users, a1 text, a2 text) RETURNS text
	AS $$
  let u = PL.to_record_exn u in
  let a1 = PL.to_string_exn a1 in
  let a2 = PL.to_string_exn a2 in
  let keys = List.sort (fun (k1, _) (k2, _) -> String.compare k1 k2) u in
  let format_val = function
    | PL.String s -> s
    | PL.Int i -> string_of_int i
    | PL.Null -> "None"
    | PL.Bool b -> string_of_bool b
    | PL.Float f -> string_of_float f
    | _ -> "unknown"
  in
  let out = List.map (fun (k, v) -> Printf.sprintf "%s: %s" k (format_val v)) keys in
  PL.String (a1 ^ " " ^ a2 ^ " => {" ^ String.concat ", " out ^ "}")
$$ LANGUAGE plocamlu;

select "Argument test #1"(users, fname, lname) from users where lname = 'doe' order by 1;


-- check module contents (dir(plpy) analog: names exported by module PL)
CREATE FUNCTION module_contents() RETURNS SETOF text AS
$$
  let env = !Toploop.toplevel_env in
  let (_, md) = Env.lookup_module ~loc:Location.none (Longident.Lident "PL") env in
  let names = ref [] in
  let rec get_names mty =
    match mty with
    | Types.Mty_signature s ->
        List.iter (fun item ->
          match item with
          | Types.Sig_value (id, _, _) -> names := Ident.name id :: !names
          | Types.Sig_type (id, _, _, _) -> names := Ident.name id :: !names
          | Types.Sig_module (id, _, _, _, _) -> names := Ident.name id :: !names
          | _ -> ()
        ) s
    | _ -> ()
  in
  get_names md.Types.md_type;
  let sorted = List.sort String.compare !names in
  PL.Array (Array.of_list (List.map (fun s -> PL.String s) sorted))
$$ LANGUAGE plocamlu;

select module_contents();

CREATE FUNCTION elog_test_basic() RETURNS void
AS $$
  PL.debug "debug";
  PL.log "log";
  PL.info "info";
  PL.info "37";
  PL.info "";
  PL.info "info 37 [1, 2, 3]";
  PL.notice "notice";
  PL.warning "warning";
  PL.error "error";
  ()
$$ LANGUAGE plocamlu;

SELECT elog_test_basic();
