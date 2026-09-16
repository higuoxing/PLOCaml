use ocaml::{sys, Value};
use pgrx::pg_sys::errcodes::PgSqlErrorCode;
use pgrx::prelude::*;
use std::ffi::CString;

unsafe extern "C-unwind" {
    fn errstart(elevel: ::std::os::raw::c_int, domain: *const ::std::os::raw::c_char) -> bool;
    fn errcode(sqlerrcode: ::std::os::raw::c_int) -> ::std::os::raw::c_int;
    fn errmsg(fmt: *const ::std::os::raw::c_char, ...) -> ::std::os::raw::c_int;
    fn errdetail(fmt: *const ::std::os::raw::c_char, ...) -> ::std::os::raw::c_int;
    fn errhint(fmt: *const ::std::os::raw::c_char, ...) -> ::std::os::raw::c_int;
    fn errcontext_msg(fmt: *const ::std::os::raw::c_char, ...) -> ::std::os::raw::c_int;
    fn err_generic_string(
        field: ::std::os::raw::c_int,
        str: *const ::std::os::raw::c_char,
    ) -> ::std::os::raw::c_int;
    fn errfinish(
        filename: *const ::std::os::raw::c_char,
        lineno: ::std::os::raw::c_int,
        funcname: *const ::std::os::raw::c_char,
    );
}

/// Diagnostic fields from `PL.error` / `PL.Error`.
#[derive(Debug, Clone)]
pub(crate) struct ErrorInfo {
    pub message: String,
    pub detail: Option<String>,
    pub hint: Option<String>,
    pub sqlstate: Option<String>,
    pub schema_name: Option<String>,
    pub table_name: Option<String>,
    pub column_name: Option<String>,
    pub datatype_name: Option<String>,
    pub constraint_name: Option<String>,
    pub context: Option<String>,
}

pub(crate) enum OcamlError {
    Postgres(ErrorInfo),
    Other(String),
}

pub(crate) unsafe fn extract_string(val: sys::Value) -> String {
    let ptr = sys::string_val(val);
    let len = sys::caml_string_length(val);
    let slice = std::slice::from_raw_parts(ptr, len);
    String::from_utf8_lossy(slice).into_owned()
}

pub(crate) unsafe fn extract_string_option(opt_val: sys::Value) -> Option<String> {
    if sys::is_block(opt_val) {
        let str_val = *sys::field(opt_val, 0);
        Some(extract_string(str_val))
    } else {
        None
    }
}

pub(crate) unsafe fn extract_error_info(info_val: sys::Value) -> ErrorInfo {
    ErrorInfo {
        message: extract_string(*sys::field(info_val, 0)),
        detail: extract_string_option(*sys::field(info_val, 1)),
        hint: extract_string_option(*sys::field(info_val, 2)),
        sqlstate: extract_string_option(*sys::field(info_val, 3)),
        schema_name: extract_string_option(*sys::field(info_val, 4)),
        table_name: extract_string_option(*sys::field(info_val, 5)),
        column_name: extract_string_option(*sys::field(info_val, 6)),
        datatype_name: extract_string_option(*sys::field(info_val, 7)),
        constraint_name: extract_string_option(*sys::field(info_val, 8)),
        context: None,
    }
}

pub(crate) fn sqlstate_to_errcode(s: &str) -> Option<i32> {
    let bytes = s.as_bytes();
    if bytes.len() == 5 {
        let pgsixbit = |ch: u8| ((ch as i32) - ('0' as i32)) & 0x3F;
        Some(
            pgsixbit(bytes[0])
                + (pgsixbit(bytes[1]) << 6)
                + (pgsixbit(bytes[2]) << 12)
                + (pgsixbit(bytes[3]) << 18)
                + (pgsixbit(bytes[4]) << 24),
        )
    } else {
        None
    }
}

unsafe fn decode_pl_error(exc: sys::Value) -> Option<ErrorInfo> {
    let decode = Value::named("plocaml_decode_error")?;
    let raw = sys::caml_callback_exn(decode.raw().0, exc);
    if sys::is_exception_result(raw) || !sys::is_block(raw) {
        return None;
    }
    Some(extract_error_info(*sys::field(raw, 0)))
}

/// Strip `Failure("…")`, `Invalid_argument("…")`, and Toploop
/// `Exception: Failure "…".` wrappers so PostgreSQL DETAIL shows the
/// inner message rather than OCaml's exception printer.
pub(crate) fn unwrap_ocaml_exception_message(s: &str) -> String {
    let mut current = s.trim().to_string();
    loop {
        let next = unwrap_ocaml_exception_once(&current);
        if next == current {
            return current.trim().to_string();
        }
        current = next;
    }
}

fn unwrap_ocaml_exception_once(s: &str) -> String {
    let s = s.trim();

    if let Some(inner) = strip_paren_string_ctor(s, "Failure") {
        return inner;
    }
    if let Some(inner) = strip_paren_string_ctor(s, "Invalid_argument") {
        return inner;
    }

    let body = s.strip_prefix("Exception:").map(str::trim).unwrap_or(s);

    if let Some(inner) = strip_quoted_string_ctor(body, "Failure") {
        return inner;
    }
    if let Some(inner) = strip_quoted_string_ctor(body, "Invalid_argument") {
        return inner;
    }

    s.to_string()
}

/// `Failure("msg")` / `Invalid_argument("msg")` from `caml_format_exception`.
/// Inner quotes are not escaped, so take everything up to the last `")`.
fn strip_paren_string_ctor(s: &str, ctor: &str) -> Option<String> {
    let prefix = format!("{ctor}(\"");
    let rest = s.strip_prefix(&prefix)?;
    let rest = rest.trim_end();
    let inner = rest.strip_suffix("\")")?;
    Some(inner.to_string())
}

/// Toploop / compiler printer: `Failure "msg"` or a line-wrapped
/// `Failure\n "msg"`, optionally followed by `.`.
fn strip_quoted_string_ctor(s: &str, ctor: &str) -> Option<String> {
    let rest = s.strip_prefix(ctor)?;
    let rest = rest.trim_start();
    let (inner, after) = parse_ocaml_quoted_string(rest)?;
    let after = after
        .trim()
        .strip_prefix('.')
        .unwrap_or(after.trim())
        .trim();
    if after.is_empty() {
        Some(inner)
    } else {
        None
    }
}

fn parse_ocaml_quoted_string(s: &str) -> Option<(String, &str)> {
    let s = s.trim_start();
    let mut chars = s.char_indices();
    if chars.next()?.1 != '"' {
        return None;
    }
    let mut out = String::new();
    while let Some((i, ch)) = chars.next() {
        match ch {
            '"' => return Some((out, &s[i + 1..])),
            '\\' => {
                let (_, esc) = chars.next()?;
                match esc {
                    'n' => out.push('\n'),
                    't' => out.push('\t'),
                    'r' => out.push('\r'),
                    'b' => out.push('\u{0008}'),
                    '\\' | '"' | '\'' | ' ' => out.push(esc),
                    'x' => {
                        let (_, h1) = chars.next()?;
                        let (_, h2) = chars.next()?;
                        let hex = format!("{h1}{h2}");
                        let byte = u8::from_str_radix(&hex, 16).ok()?;
                        out.push(byte as char);
                    }
                    d if d.is_ascii_digit() => {
                        let mut digits = String::from(d);
                        for _ in 0..2 {
                            let saved = chars.clone();
                            match chars.next() {
                                Some((_, c)) if c.is_ascii_digit() => digits.push(c),
                                _ => {
                                    chars = saved;
                                    break;
                                }
                            }
                        }
                        let byte = digits.parse::<u8>().ok()?;
                        out.push(byte as char);
                    }
                    other => out.push(other),
                }
            }
            other => out.push(other),
        }
    }
    None
}

unsafe fn take_runtime_backtrace() -> Option<String> {
    let take = Value::named("plocaml_take_backtrace")?;
    let raw = sys::caml_callback_exn(take.raw().0, sys::UNIT);
    if sys::is_exception_result(raw) {
        return None;
    }
    extract_string_option(raw)
}

/// Safely invokes an OCaml closure with arguments, catching any OCaml exceptions
/// without triggering `ocaml-rs`'s buggy `caml_modify` on stack variables.
pub(crate) unsafe fn call_exn(closure: Value, args: &[Value]) -> Result<Value, OcamlError> {
    let raw_res = match args {
        [] => sys::caml_callback_exn(closure.raw().0, sys::UNIT),
        [arg] => sys::caml_callback_exn(closure.raw().0, arg.raw().0),
        _ => {
            let mut raw_args: Vec<sys::Value> = args.iter().map(|v| v.raw().0).collect();
            sys::caml_callbackN_exn(closure.raw().0, raw_args.len(), raw_args.as_mut_ptr())
        }
    };

    if sys::is_exception_result(raw_res) {
        let exc = sys::extract_exception(raw_res);
        let context = take_runtime_backtrace();
        if let Some(mut info) = decode_pl_error(exc) {
            info.context = context;
            Err(OcamlError::Postgres(info))
        } else {
            let exc_val = Value::new(exc);
            let msg = exc_val
                .exception_to_string()
                .unwrap_or_else(|_| "Unknown OCaml exception".to_string());
            Err(OcamlError::Postgres(ErrorInfo {
                message: unwrap_ocaml_exception_message(&msg),
                detail: None,
                hint: None,
                sqlstate: None,
                schema_name: None,
                table_name: None,
                column_name: None,
                datatype_name: None,
                constraint_name: None,
                context,
            }))
        }
    } else {
        Ok(Value::new(raw_res))
    }
}

/// Report an uncaught `PL.error` with first-class PostgreSQL diagnostic fields,
/// matching PL/Python's `plpy.error(...)` (message / DETAIL / HINT / SQLSTATE).
pub(crate) fn raise_postgres_error(info: ErrorInfo) -> ! {
    let sqlerrcode = info
        .sqlstate
        .as_deref()
        .and_then(sqlstate_to_errcode)
        .unwrap_or(PgSqlErrorCode::ERRCODE_EXTERNAL_ROUTINE_EXCEPTION as i32);

    unsafe {
        if errstart(pg_sys::PGERROR as i32, std::ptr::null()) {
            let msg_c = CString::new(info.message.as_str()).unwrap_or_default();
            errmsg(c"%s".as_ptr(), msg_c.as_ptr());
            errcode(sqlerrcode as ::std::os::raw::c_int);

            let detail_c = info
                .detail
                .as_ref()
                .map(|d| CString::new(d.as_str()).unwrap_or_default());
            if let Some(d) = &detail_c {
                errdetail(c"%s".as_ptr(), d.as_ptr());
            }
            let hint_c = info
                .hint
                .as_ref()
                .map(|h| CString::new(h.as_str()).unwrap_or_default());
            if let Some(h) = &hint_c {
                errhint(c"%s".as_ptr(), h.as_ptr());
            }
            let context_c = info
                .context
                .as_ref()
                .map(|c| CString::new(c.as_str()).unwrap_or_default());
            if let Some(ctx) = &context_c {
                errcontext_msg(c"%s".as_ptr(), ctx.as_ptr());
            }
            let schema_c = info
                .schema_name
                .as_ref()
                .map(|s| CString::new(s.as_str()).unwrap_or_default());
            if let Some(s) = &schema_c {
                err_generic_string(pg_sys::PG_DIAG_SCHEMA_NAME as i32, s.as_ptr());
            }
            let table_c = info
                .table_name
                .as_ref()
                .map(|s| CString::new(s.as_str()).unwrap_or_default());
            if let Some(s) = &table_c {
                err_generic_string(pg_sys::PG_DIAG_TABLE_NAME as i32, s.as_ptr());
            }
            let column_c = info
                .column_name
                .as_ref()
                .map(|s| CString::new(s.as_str()).unwrap_or_default());
            if let Some(s) = &column_c {
                err_generic_string(pg_sys::PG_DIAG_COLUMN_NAME as i32, s.as_ptr());
            }
            let datatype_c = info
                .datatype_name
                .as_ref()
                .map(|s| CString::new(s.as_str()).unwrap_or_default());
            if let Some(s) = &datatype_c {
                err_generic_string(pg_sys::PG_DIAG_DATATYPE_NAME as i32, s.as_ptr());
            }
            let constraint_c = info
                .constraint_name
                .as_ref()
                .map(|s| CString::new(s.as_str()).unwrap_or_default());
            if let Some(s) = &constraint_c {
                err_generic_string(pg_sys::PG_DIAG_CONSTRAINT_NAME as i32, s.as_ptr());
            }

            let file_c = c"plocaml";
            let func_c = c"plocaml_error";
            errfinish(file_c.as_ptr(), 0, func_c.as_ptr());
        }
    }

    ereport!(
        ERROR,
        PgSqlErrorCode::ERRCODE_EXTERNAL_ROUTINE_EXCEPTION,
        info.message
    );
}

/// Push `PL/OCaml function "name"` (or anonymous code block) onto
/// PostgreSQL's error_context_stack for the duration of a call/DO.
pub(crate) struct ErrorContextGuard {
    previous: *mut pg_sys::ErrorContextCallback,
    _name: CString,
    cb: Box<pg_sys::ErrorContextCallback>,
}

impl ErrorContextGuard {
    pub(crate) fn push(name: &str) -> Self {
        let name_c = CString::new(name).unwrap_or_default();
        let previous = unsafe { pg_sys::error_context_stack };
        let mut cb = Box::new(pg_sys::ErrorContextCallback {
            previous,
            callback: Some(plocaml_error_callback),
            arg: std::ptr::null_mut(),
        });
        cb.arg = name_c.as_ptr() as *mut std::ffi::c_void;
        unsafe {
            pg_sys::error_context_stack = cb.as_mut();
        }
        Self {
            previous,
            _name: name_c,
            cb,
        }
    }
}

impl Drop for ErrorContextGuard {
    fn drop(&mut self) {
        unsafe {
            pg_sys::error_context_stack = self.previous;
        }
        let _keep = self.cb.previous;
    }
}

unsafe extern "C-unwind" fn plocaml_error_callback(arg: *mut std::ffi::c_void) {
    let name = std::ffi::CStr::from_ptr(arg as *const std::os::raw::c_char);
    if name.to_bytes().is_empty() {
        errcontext_msg(c"%s".as_ptr(), c"PL/OCaml anonymous code block".as_ptr());
    } else {
        errcontext_msg(c"PL/OCaml function \"%s\"".as_ptr(), arg);
    }
}

/// Report a generic uncaught OCaml exception as a PostgreSQL error.
///
/// The inner message is the ERROR text (same as `PL.error` / PL/Python),
/// not a `PL/OCaml execution failed` wrapper with the real text in DETAIL.
pub(crate) fn raise_ocaml_error(err: OcamlError) -> ! {
    match err {
        OcamlError::Postgres(info) => raise_postgres_error(info),
        OcamlError::Other(detail) => raise_postgres_error(ErrorInfo {
            message: unwrap_ocaml_exception_message(&detail),
            detail: None,
            hint: None,
            sqlstate: None,
            schema_name: None,
            table_name: None,
            column_name: None,
            datatype_name: None,
            constraint_name: None,
            context: None,
        }),
    }
}

#[cfg(test)]
mod unwrap_tests {
    use super::unwrap_ocaml_exception_message;

    #[test]
    fn unwraps_failure_paren() {
        assert_eq!(unwrap_ocaml_exception_message(r#"Failure("boom")"#), "boom");
        assert_eq!(
            unwrap_ocaml_exception_message(r#"Failure("syntax error at or near "syntax"")"#),
            r#"syntax error at or near "syntax""#
        );
        assert_eq!(
            unwrap_ocaml_exception_message(
                r#"Failure("File "_none_", line 8, characters 2-5:
Error: Syntax error
")"#
            ),
            "File \"_none_\", line 8, characters 2-5:\nError: Syntax error"
        );
    }

    #[test]
    fn unwraps_invalid_argument() {
        assert_eq!(
            unwrap_ocaml_exception_message(r#"Invalid_argument("index out of bounds")"#),
            "index out of bounds"
        );
    }

    #[test]
    fn unwraps_toploop_exception_failure() {
        assert_eq!(
            unwrap_ocaml_exception_message(r#"Failure("Exception: Failure "error test".")"#),
            "error test"
        );
        assert_eq!(
            unwrap_ocaml_exception_message(
                r#"Failure("Exception: Failure "cannot commit while a subtransaction is active".")"#
            ),
            "cannot commit while a subtransaction is active"
        );
        assert_eq!(
            unwrap_ocaml_exception_message(
                "Failure(\"Exception:\nFailure\n \"insert or update on table \\\"testfk\\\" violates foreign key constraint \\\"testfk_f1_fkey\\\"\".\")"
            ),
            r#"insert or update on table "testfk" violates foreign key constraint "testfk_f1_fkey""#
        );
    }

    #[test]
    fn leaves_plain_messages_alone() {
        assert_eq!(
            unwrap_ocaml_exception_message("Unsupported return value tag 4 for PostgreSQL type 25"),
            "Unsupported return value tag 4 for PostgreSQL type 25"
        );
        assert_eq!(
            unwrap_ocaml_exception_message("Env.Error(_)"),
            "Env.Error(_)"
        );
    }
}
