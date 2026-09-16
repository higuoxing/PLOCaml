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

    (* Filled at PL.error / uncaught Failure so Rust can put it in CONTEXT.
       Compile failures set [suppress_backtrace] so Toploop frames stay out. *)
    let runtime_backtrace : string option ref = ref None
    let suppress_backtrace = ref false

    let is_user_source_file f =
      f <> "" && f <> "<plocaml-wrapper>" && f <> "_none_"
      && (not (String.contains f '/'))
      && (not (Filename.check_suffix f ".ml"))
      && (not (Filename.check_suffix f ".mli"))
      && not (Filename.check_suffix f ".c")

    let display_frame_name s =
      let prefix = "__plocaml_fn_" in
      let plen = String.length prefix in
      if String.length s >= plen && String.sub s 0 plen = prefix then
        let rec skip_digits i =
          if i < String.length s && s.[i] >= '0' && s.[i] <= '9' then
            skip_digits (i + 1)
          else i
        in
        let i = skip_digits plen in
        if i < String.length s && s.[i] = '.' then
          String.sub s (i + 1) (String.length s - i - 1)
        else "<function>"
      else s

    let parse_backtrace_frame line =
      let markers =
        [
          "Raised by primitive operation at ";
          "Raised at ";
          "Re-raised at ";
          "Called from ";
        ]
      in
      let rec strip ms =
        match ms with
        | [] -> line
        | m :: rest ->
            let ml = String.length m in
            if String.length line >= ml && String.sub line 0 ml = m then
              String.sub line ml (String.length line - ml)
            else strip rest
      in
      let rest = strip markers in
      let key = " in file \"" in
      match
        let rec find i =
          if i + String.length key > String.length rest then None
          else if String.sub rest i (String.length key) = key then Some i
          else find (i + 1)
        in
        find 0
      with
      | None -> None
      | Some i -> (
          let name = String.trim (String.sub rest 0 i) in
          let after =
            String.sub rest
              (i + String.length key)
              (String.length rest - i - String.length key)
          in
          match String.index_opt after '"' with
          | None -> None
          | Some q -> (
              let file = String.sub after 0 q in
              let tail =
                String.sub after (q + 1) (String.length after - q - 1)
              in
              let line_key = ", line " in
              let rec find_line i =
                if i + String.length line_key > String.length tail then None
                else if String.sub tail i (String.length line_key) = line_key
                then Some i
                else find_line (i + 1)
              in
              match find_line 0 with
              | None -> None
              | Some li ->
                  let num =
                    String.sub tail
                      (li + String.length line_key)
                      (String.length tail - li - String.length line_key)
                  in
                  let rec take_digits s acc j =
                    if j < String.length s && s.[j] >= '0' && s.[j] <= '9' then
                      take_digits s (acc ^ String.make 1 s.[j]) (j + 1)
                    else acc
                  in
                  let nstr = take_digits num "" 0 in
                  if nstr = "" then None
                  else Some (display_frame_name name, file, int_of_string nstr))
          )

    let format_traceback raw =
      let rec split s =
        match String.index_opt s '\n' with
        | None -> if s = "" then [] else [ s ]
        | Some i ->
            String.sub s 0 i
            :: split (String.sub s (i + 1) (String.length s - i - 1))
      in
      let frames =
        List.filter_map
          (fun line ->
            match parse_backtrace_frame (String.trim line) with
            | Some (name, file, line_no) when is_user_source_file file ->
                Some (name, file, line_no)
            | Some (name, file, line_no) when file = "_none_" ->
                Some (name, file, line_no)
            | _ -> None)
          (split raw)
      in
      match List.rev frames with
      | [] -> None
      | frames ->
          let buf = Buffer.create 128 in
          Buffer.add_string buf "Traceback (most recent call last):";
          List.iter
            (fun (name, file, line_no) ->
              Buffer.add_char buf '\n';
              if file = "_none_" || file = "" then
                Buffer.add_string buf
                  (Printf.sprintf
                     "  PL/OCaml anonymous code block, line %d, in %s" line_no
                     name)
              else
                Buffer.add_string buf
                  (Printf.sprintf "  PL/OCaml function \"%s\", line %d, in %s"
                     file line_no name))
            frames;
          Some (Buffer.contents buf)

    let capture_callstack () =
      if !suppress_backtrace then ()
      else if !runtime_backtrace = None then
        runtime_backtrace :=
          format_traceback
            (Printexc.raw_backtrace_to_string (Printexc.get_callstack 64))

    let note_exception_backtrace () =
      if !suppress_backtrace then ()
      else if !runtime_backtrace = None then
        runtime_backtrace := format_traceback (Printexc.get_backtrace ())

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
          capture_callstack ();
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

(* PL/Python reports compile failures as
     ERROR:  could not compile PL/Python function "name"
     DETAIL: <compiler text>
   Mirror that: the OCaml location text (function name as filename, line
   numbers relative to the user body) becomes DETAIL. *)
let plocaml_raise_compile_error (name : string) (detail : string) =
  PL.Log.suppress_backtrace := true;
  Fun.protect
    ~finally:(fun () -> PL.Log.suppress_backtrace := false)
    (fun () ->
      PL.error ~detail
        (Printf.sprintf "could not compile PL/OCaml function \"%s\"" name))

let plocaml_note_exception_backtrace () = PL.Log.note_exception_backtrace ()

let plocaml_take_backtrace () : string option =
  let bt = !PL.Log.runtime_backtrace in
  PL.Log.runtime_backtrace := None;
  bt

let decode_error (exn : exn) =
  match exn with PL.Error info -> Some info | _ -> None

let reraise_pending_error () =
  match !PL.Log.pending_error with
  | None -> ()
  | Some info ->
      PL.Log.pending_error := None;
      raise (PL.Error info)

let () =
  Callback.register "plocaml_decode_error" decode_error;
  Callback.register "plocaml_take_backtrace" plocaml_take_backtrace
