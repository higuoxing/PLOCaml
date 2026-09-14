module Plocaml = struct
  type plan
  type cursor

  type datum =
    | Null
    | Int of int
    | Float of float
    | String of string
    | Bool of bool
    | Array of datum array
    | Record of (string * datum) list

  type spi_result = {
    status : int;
    nrows : int;
    rows : (string * datum) list array;
  }

  type log_level =
    | Debug5
    | Debug4
    | Debug3
    | Debug2
    | Debug1
    | Log
    | Info
    | Notice
    | Warning
    | Error

  type error_info = {
    e_message : string;
    e_detail : string option;
    e_hint : string option;
    e_sqlstate : string option;
    e_schema_name : string option;
    e_table_name : string option;
    e_column_name : string option;
    e_datatype_name : string option;
    e_constraint_name : string option;
  }

  (* SPI Operations *)
  module SPI = struct
    external execute : string -> spi_result = "plocaml_spi_execute"
    external prepare : string -> string array -> plan = "plocaml_spi_prepare"

    external execute_plan : plan -> datum array -> spi_result
      = "plocaml_spi_execute_plan"

    external cursor : string -> cursor = "plocaml_spi_cursor_open"

    external cursor_plan : plan -> datum array -> cursor
      = "plocaml_spi_cursor_open_plan"

    external fetch : cursor -> int -> spi_result = "plocaml_spi_cursor_fetch"
    external close : cursor -> unit = "plocaml_spi_cursor_close"
  end

  (* Logging and Error Reporting *)
  module Log = struct
    external elog_record : log_level -> error_info -> unit = "plocaml_elog"

    exception Error of error_info

    let pending_error : error_info option ref = ref None

    let report (level : log_level) ?detail ?hint ?sqlstate ?schema_name
        ?table_name ?column_name ?datatype_name ?constraint_name
        (message : string) : unit =
      let info =
        {
          e_message = message;
          e_detail = detail;
          e_hint = hint;
          e_sqlstate = sqlstate;
          e_schema_name = schema_name;
          e_table_name = table_name;
          e_column_name = column_name;
          e_datatype_name = datatype_name;
          e_constraint_name = constraint_name;
        }
      in
      match level with
      | Error ->
          pending_error := Some info;
          raise (Error info)
      | _ -> elog_record level info

    let debug ?detail ?hint ?sqlstate ?schema_name ?table_name ?column_name
        ?datatype_name ?constraint_name message =
      report Debug1 ?detail ?hint ?sqlstate ?schema_name ?table_name
        ?column_name ?datatype_name ?constraint_name message

    let log ?detail ?hint ?sqlstate ?schema_name ?table_name ?column_name
        ?datatype_name ?constraint_name message =
      report Log ?detail ?hint ?sqlstate ?schema_name ?table_name ?column_name
        ?datatype_name ?constraint_name message

    let info ?detail ?hint ?sqlstate ?schema_name ?table_name ?column_name
        ?datatype_name ?constraint_name message =
      report Info ?detail ?hint ?sqlstate ?schema_name ?table_name ?column_name
        ?datatype_name ?constraint_name message

    let notice ?detail ?hint ?sqlstate ?schema_name ?table_name ?column_name
        ?datatype_name ?constraint_name message =
      report Notice ?detail ?hint ?sqlstate ?schema_name ?table_name
        ?column_name ?datatype_name ?constraint_name message

    let warning ?detail ?hint ?sqlstate ?schema_name ?table_name ?column_name
        ?datatype_name ?constraint_name message =
      report Warning ?detail ?hint ?sqlstate ?schema_name ?table_name
        ?column_name ?datatype_name ?constraint_name message

    let error ?detail ?hint ?sqlstate ?schema_name ?table_name ?column_name
        ?datatype_name ?constraint_name message =
      report Error ?detail ?hint ?sqlstate ?schema_name ?table_name ?column_name
        ?datatype_name ?constraint_name message;
      failwith "PL.error"

    let elog (level : log_level) (message : string) : unit =
      report level message
  end

  (* String Quoting *)
  module Quote = struct
    external literal : string -> string = "plocaml_quote_literal"
    external ident : string -> string = "plocaml_quote_ident"

    let nullable (s : string option) : string =
      match s with None -> "NULL" | Some s -> literal s
  end

  (* Transaction & Subtransaction Control *)
  external subtransaction : (unit -> 'a) -> 'a = "plocaml_subtransaction"
  external commit : unit -> unit = "plocaml_commit"
  external rollback : unit -> unit = "plocaml_rollback"

  (* Session / Function Storage *)
  type store = (string, Obj.t) Hashtbl.t

  let gd : store = Hashtbl.create 16
  let sd_map : (int, store) Hashtbl.t = Hashtbl.create 16

  let get_sd (oid : int) : store =
    match Hashtbl.find_opt sd_map oid with
    | Some s -> s
    | None ->
        let s = Hashtbl.create 16 in
        Hashtbl.add sd_map oid s;
        s

  (* Unwrap `datum` values and SD/GD entries. Arguments arrive as the
     `datum` ADT, so user code needs a small conversion layer. *)
  let to_int_exn = function
    | Int x -> x
    | _ -> failwith "PL/OCaml: Expected Int"

  let to_float_exn = function
    | Float x -> x
    | _ -> failwith "PL/OCaml: Expected Float"

  let to_string_exn = function
    | String x -> x
    | _ -> failwith "PL/OCaml: Expected String"

  let to_bool_exn = function
    | Bool x -> x
    | _ -> failwith "PL/OCaml: Expected Bool"

  let to_array_exn = function
    | Array x -> x
    | _ -> failwith "PL/OCaml: Expected Array"

  let to_record_exn = function
    | Record x -> x
    | _ -> failwith "PL/OCaml: Expected Record"

  let to_int_opt = function Int x -> Some x | _ -> None
  let to_float_opt = function Float x -> Some x | _ -> None
  let to_string_opt = function String x -> Some x | _ -> None
  let to_bool_opt = function Bool x -> Some x | _ -> None
  let to_array_opt = function Array x -> Some x | _ -> None
  let to_record_opt = function Record x -> Some x | _ -> None
  let to_int ~default = function Int x -> x | _ -> default
  let to_float ~default = function Float x -> x | _ -> default
  let to_string ~default = function String x -> x | _ -> default
  let to_bool ~default = function Bool x -> x | _ -> default
  let to_array ~default = function Array x -> x | _ -> default

  (* GD/SD store helpers. The type read back MUST match the type written. *)
  let set (t : store) (key : string) (v : 'a) : unit =
    Hashtbl.replace t key (Obj.repr v)

  let get_opt (t : store) (key : string) : 'a option =
    match Hashtbl.find_opt t key with
    | Some v -> Some (Obj.obj v)
    | None -> None

  let get (t : store) (key : string) : 'a =
    match Hashtbl.find_opt t key with
    | Some v -> Obj.obj v
    | None ->
        failwith (Printf.sprintf "PL/OCaml: no GD/SD entry for key %S" key)

  (* Direct convenience shortcuts on Plocaml / PL *)
  let execute = SPI.execute
  let prepare = SPI.prepare
  let execute_plan = SPI.execute_plan
  let cursor = SPI.cursor
  let cursor_plan = SPI.cursor_plan
  let fetch = SPI.fetch
  let close = SPI.close
  let debug = Log.debug
  let log = Log.log
  let info = Log.info
  let notice = Log.notice
  let warning = Log.warning
  let error = Log.error
  let elog = Log.elog
  let report = Log.report
  let quote_literal = Quote.literal
  let quote_nullable = Quote.nullable
  let quote_ident = Quote.ident
  let get_sd = get_sd

  exception Error = Log.Error
end

module PL = Plocaml

let decode_error (exn : exn) =
  match exn with PL.Error info -> Some info | _ -> None

let reraise_pending_error () =
  match !PL.Log.pending_error with
  | None -> ()
  | Some info ->
      PL.Log.pending_error := None;
      raise (PL.Error info)

let () = Callback.register "plocaml_decode_error" decode_error
