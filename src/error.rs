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
        if let Some(info) = decode_pl_error(exc) {
            Err(OcamlError::Postgres(info))
        } else {
            let exc_val = Value::new(exc);
            let msg = exc_val
                .exception_to_string()
                .unwrap_or_else(|_| "Unknown OCaml exception".to_string());
            Err(OcamlError::Other(msg))
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

/// Report a generic uncaught OCaml exception as a PostgreSQL error.
pub(crate) fn raise_ocaml_error(err: OcamlError) -> ! {
    match err {
        OcamlError::Postgres(info) => raise_postgres_error(info),
        OcamlError::Other(detail) => {
            ereport!(
                ERROR,
                PgSqlErrorCode::ERRCODE_EXTERNAL_ROUTINE_EXCEPTION,
                "PL/OCaml execution failed",
                detail
            );
        }
    }
}
