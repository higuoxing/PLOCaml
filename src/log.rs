use crate::error::{extract_error_info, sqlstate_to_errcode};
use pgrx::pg_sys;
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

/// Emit a PostgreSQL log message. ERROR is raised as `PL.Error` on the OCaml
/// side so it stays catchable; this path only handles non-error elevels.
#[no_mangle]
pub unsafe extern "C" fn plocaml_elog(
    level_val: ocaml::sys::Value,
    info_val: ocaml::sys::Value,
) -> ocaml::sys::Value {
    let tag = ocaml::sys::int_val(level_val);
    let info = extract_error_info(info_val);

    let elevel = match tag {
        0 => pg_sys::DEBUG5 as i32,
        1 => pg_sys::DEBUG4 as i32,
        2 => pg_sys::DEBUG3 as i32,
        3 => pg_sys::DEBUG2 as i32,
        4 => pg_sys::DEBUG1 as i32,
        5 => pg_sys::LOG as i32,
        6 => pg_sys::INFO as i32,
        7 => pg_sys::NOTICE as i32,
        8 => pg_sys::WARNING as i32,
        9 => {
            // Fallback if OCaml ever calls elog at ERROR: raise Failure with
            // the message only so DETAIL/HINT stay first-class on PL.Error.
            let c_str = CString::new(info.message.as_str())
                .unwrap_or_else(|_| CString::new("PL/OCaml error").unwrap());
            ocaml::sys::caml_failwith(c_str.as_ptr());
            unreachable!()
        }
        _ => pg_sys::NOTICE as i32,
    };

    let domain_ptr: *const std::os::raw::c_char = std::ptr::null();
    if errstart(elevel, domain_ptr) {
        let msg_c = CString::new(info.message.as_str()).unwrap_or_default();
        errmsg(c"%s".as_ptr(), msg_c.as_ptr());

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
        if let Some(s) = &info.sqlstate {
            if let Some(code) = sqlstate_to_errcode(s) {
                errcode(code as ::std::os::raw::c_int);
            }
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
        let func_c = c"plocaml_elog";
        errfinish(file_c.as_ptr(), 0, func_c.as_ptr());
    }

    ocaml::sys::UNIT
}
