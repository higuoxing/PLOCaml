use crate::pg_finfo_v1;
use pgrx::prelude::*;
use std::ffi::CStr;

pub(crate) fn function_name(oid: pg_sys::Oid) -> String {
    unsafe {
        let ptr = pg_sys::get_func_name(oid);
        if ptr.is_null() {
            return "<unknown>".to_string();
        }
        let name = CStr::from_ptr(ptr).to_string_lossy().into_owned();
        pg_sys::pfree(ptr.cast());
        name
    }
}

fn is_event_trigger_oid(oid: pg_sys::Oid) -> bool {
    // PG 13 names this EVTTRIGGEROID; PG 14+ use EVENT_TRIGGEROID.
    #[cfg(feature = "pg13")]
    {
        oid == pg_sys::EVTTRIGGEROID
    }
    #[cfg(not(feature = "pg13"))]
    {
        oid == pg_sys::EVENT_TRIGGEROID
    }
}

unsafe fn arg_names_array(pronargs: usize, proargnames: &[Option<String>]) -> ocaml::Value {
    let names_arr = ocaml::sys::caml_alloc(pronargs, 0);
    let names_arr_val = ocaml::Value::new(names_arr);
    for i in 0..pronargs {
        let name_str = proargnames.get(i).and_then(|n| n.as_deref()).unwrap_or("");
        let name_val = ocaml::Value::string(name_str);
        *ocaml::sys::field(names_arr_val.raw().0, i) = name_val.raw().0;
    }
    names_arr_val
}

/// Compile and cache the function without running it. Failed compiles do not
/// leave a `compiled_functions` entry (Hashtbl.replace happens only after
/// a successful Toploop define).
pub(crate) unsafe fn compile_plocaml_function(
    fn_oid: pg_sys::Oid,
    proname: &str,
    prosrc: &str,
    pronargs: usize,
    proargnames: &[Option<String>],
) {
    let names_arr_val = arg_names_array(pronargs, proargnames);
    let compile_fn = ocaml::Value::named("plocaml_compile_function")
        .unwrap_or_else(|| pgrx::error!("plocaml_compile_function callback not registered"));
    let fn_oid_val = ocaml::Value::new(ocaml::sys::val_int(fn_oid.to_u32() as isize));
    let proname_val = ocaml::Value::string(proname);
    let prosrc_val = ocaml::Value::string(prosrc);
    match crate::error::call_exn(
        compile_fn,
        &[fn_oid_val, proname_val, prosrc_val, names_arr_val],
    ) {
        Ok(_) => {}
        Err(err) => crate::error::raise_ocaml_error(err),
    }
}

/// CREATE FUNCTION validator. Honors `check_function_bodies` like PL/Python:
/// signature checks always run; body compile runs only when the GUC is on.
pg_finfo_v1!(pg_finfo_plocaml_validator);

#[no_mangle]
#[pg_guard]
pub extern "C-unwind" fn plocaml_validator(fcinfo: pg_sys::FunctionCallInfo) -> pg_sys::Datum {
    if fcinfo.is_null() {
        pgrx::error!("plocaml_validator: fcinfo is null");
    }

    let funcoid = unsafe {
        let slice = (*fcinfo).args.as_slice(1);
        pg_sys::Oid::from(slice[0].value.value() as u32)
    };
    let validator_oid = unsafe { (*(*fcinfo).flinfo).fn_oid };

    unsafe {
        if !pg_sys::CheckFunctionValidatorAccess(validator_oid, funcoid) {
            return pg_sys::Datum::from(0);
        }
    }

    let (prosrc, pronargs, proargnames, prorettype) = {
        let proc = match pgrx::pg_catalog::pg_proc::PgProc::new(funcoid) {
            Some(p) => p,
            None => pgrx::error!(
                "plocaml_validator: pg_proc entry not found for OID {:?}",
                funcoid
            ),
        };
        (
            proc.prosrc(),
            proc.pronargs(),
            proc.proargnames(),
            proc.prorettype(),
        )
    };

    if prorettype == pg_sys::TRIGGEROID || is_event_trigger_oid(prorettype) {
        pgrx::error!("PL/OCaml: triggers are not yet supported");
    }

    // pg_dump sets check_function_bodies=off so restore can create functions
    // whose bodies depend on objects that are not loaded yet.
    if unsafe { pg_sys::check_function_bodies } {
        let proname = function_name(funcoid);
        unsafe {
            compile_plocaml_function(funcoid, &proname, &prosrc, pronargs, &proargnames);
        }
    }

    unsafe {
        (*fcinfo).isnull = false;
    }
    pg_sys::Datum::from(0)
}
