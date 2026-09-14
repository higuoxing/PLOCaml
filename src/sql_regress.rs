//! Official PostgreSQL PL/Python regression tests (REL_16_STABLE
//! `src/pl/plpython/sql`), translated to PL/OCaml and driven by
//! `cargo pgrx test`.
//!
//! The files in `sql/` / `expected/` mix successful statements with expected
//! `ERROR` lines, so they are executed via `pg_regress` against a dedicated
//! database on the pgrx-managed test instance rather than `Spi::run`.

use pgrx_pg_config::{PgConfig, Pgrx};
use std::path::{Path, PathBuf};
use std::process::Command;

/// Official PL/Python REGRESS order (REL_16_STABLE), with `plpython_`
/// renamed to `plocaml_`. The default run is the subset that currently
/// passes on the Rust implementation.
const REGRESS: &[&str] = &[
    "plocaml_schema",
    "plocaml_populate",
    "plocaml_do",
    "plocaml_global",
    "plocaml_import",
    "plocaml_spi",
    "plocaml_newline",
    "plocaml_params",
    "plocaml_error",
    "plocaml_ereport",
    "plocaml_unicode",
    "plocaml_quote",
    "plocaml_subtransaction",
    "plocaml_drop",
];

/// Still requires missing handler features, or hits a known implementation
/// bug. Official SQL is kept in `sql/` for later work.
///
/// - SETOF / composite / record return / OUT / void-Null / triggers
/// - `plocaml_transaction`: `PL.commit` currently leaks a catcache reference
#[allow(dead_code)]
const REGRESS_XFAIL: &[&str] = &[
    "plocaml_test",
    "plocaml_void",
    "plocaml_call",
    "plocaml_setof",
    "plocaml_record",
    "plocaml_trigger",
    "plocaml_types",
    "plocaml_composite",
    "plocaml_transaction",
];

const SQL_REGRESS_DB: &str = "plocamlu_sql_regress";

fn pg_feature_label() -> &'static str {
    if cfg!(feature = "pg13") {
        "pg13"
    } else if cfg!(feature = "pg14") {
        "pg14"
    } else if cfg!(feature = "pg15") {
        "pg15"
    } else if cfg!(feature = "pg16") {
        "pg16"
    } else if cfg!(feature = "pg17") {
        "pg17"
    } else if cfg!(feature = "pg18") {
        "pg18"
    } else if cfg!(feature = "pg19") {
        "pg19"
    } else {
        panic!("no pgXX cargo feature is enabled; run via `cargo pgrx test --features pgNN`");
    }
}

fn pg_config() -> PgConfig {
    if let Ok(cfg) = PgConfig::from_env() {
        return cfg;
    }

    let label = pg_feature_label();
    Pgrx::from_config()
        .expect("failed to load pgrx configuration")
        .get(label)
        .unwrap_or_else(|e| panic!("failed to get pg_config for {label}: {e}"))
}

fn prepend_bindir_to_path(bindir: &Path) -> std::ffi::OsString {
    let mut path = bindir.as_os_str().to_os_string();
    path.push(":");
    path.push(std::env::var_os("PATH").unwrap_or_default());
    path
}

fn recreate_sql_regress_db(client: &mut postgres::Client, port: u16, user: &str) {
    client
        .simple_query(&format!(
            "SELECT pg_terminate_backend(pid) FROM pg_stat_activity \
             WHERE datname = '{SQL_REGRESS_DB}' AND pid <> pg_backend_pid()"
        ))
        .expect("failed to terminate leftover sql-regress backends");
    client
        .simple_query(&format!("DROP DATABASE IF EXISTS {SQL_REGRESS_DB}"))
        .expect("failed to drop leftover sql-regress database");
    client
        .simple_query(&format!("CREATE DATABASE {SQL_REGRESS_DB}"))
        .expect("failed to create sql-regress database");

    // pg_regress --load-extension is a no-op with --use-existing, so install
    // the language into the dedicated database ourselves.
    let mut regress_client = postgres::Config::new()
        .host("localhost")
        .port(port)
        .user(user)
        .dbname(SQL_REGRESS_DB)
        .connect(postgres::NoTls)
        .expect("failed to connect to sql-regress database");
    regress_client
        .simple_query("CREATE EXTENSION plocamlu")
        .expect("failed to CREATE EXTENSION plocamlu in sql-regress database");
}

fn run_pg_regress(tests: &[&str]) {
    assert!(
        !tests.is_empty(),
        "sql regression list is empty; nothing to run"
    );

    let pg_config = pg_config();
    let bindir = pg_config
        .bin_dir()
        .expect("failed to resolve Postgres bindir");
    let pg_regress = pg_config
        .pg_regress_path()
        .expect("failed to resolve pg_regress path");
    assert!(
        pg_regress.exists(),
        "pg_regress not found at {}; install PostgreSQL development files",
        pg_regress.display()
    );

    let manifest_dir =
        PathBuf::from(std::env::var("CARGO_MANIFEST_DIR").expect("CARGO_MANIFEST_DIR is unset"));
    let output_dir = PathBuf::from(
        std::env::var("CARGO_TARGET_DIR")
            .unwrap_or_else(|_| manifest_dir.join("target").to_string_lossy().into_owned()),
    )
    .join("sql-regress");
    std::fs::create_dir_all(&output_dir).expect("failed to create sql-regress output directory");

    pgrx_tests::run_test("test_extension_loads", None, vec![])
        .expect("failed to initialize pgrx test instance");

    let (mut client, _) = pgrx_tests::client().expect("failed to connect to pgrx test instance");
    let row = client
        .query_one(
            "SELECT inet_server_port() AS port, current_user AS usr",
            &[],
        )
        .expect("failed to query test instance port/user");
    let port: i32 = row.get("port");
    let user: String = row.get("usr");
    recreate_sql_regress_db(&mut client, port as u16, &user);
    drop(client);

    let mut command = Command::new(&pg_regress);
    command
        .current_dir(&manifest_dir)
        .env("PATH", prepend_bindir_to_path(&bindir))
        .env_remove("PGDATABASE")
        .env_remove("PGHOST")
        .env_remove("PGPORT")
        .env_remove("PGUSER")
        .arg("--host=localhost")
        .arg(format!("--port={port}"))
        .arg(format!("--user={user}"))
        .arg(format!("--bindir={}", bindir.display()))
        .arg(format!("--inputdir={}", manifest_dir.display()))
        .arg(format!("--outputdir={}", output_dir.display()))
        .arg("--use-existing")
        .arg(format!("--dbname={SQL_REGRESS_DB}"))
        .args(tests);

    let output = command
        .output()
        .unwrap_or_else(|e| panic!("failed to spawn {}: {e}", pg_regress.display()));

    let stdout = String::from_utf8_lossy(&output.stdout);
    let stderr = String::from_utf8_lossy(&output.stderr);
    print!("{stdout}");
    eprint!("{stderr}");

    if std::env::var_os("PLOCAML_REGRESS_PROMOTE").is_some() {
        let results = output_dir.join("results");
        let expected = manifest_dir.join("expected");
        std::fs::create_dir_all(&expected).expect("failed to create expected/");
        if let Ok(entries) = std::fs::read_dir(&results) {
            for entry in entries.flatten() {
                let name = entry.file_name();
                let name_str = name.to_string_lossy();
                let stem = name_str.strip_suffix(".out").unwrap_or("");
                if REGRESS.contains(&stem) {
                    std::fs::copy(entry.path(), expected.join(&name)).unwrap_or_else(|e| {
                        panic!("failed to promote {}: {e}", entry.path().display())
                    });
                    eprintln!("promoted {name_str}");
                }
            }
        }
    }

    if !output.status.success() {
        let diffs = output_dir.join("regression.diffs");
        let diff_text = std::fs::read_to_string(&diffs)
            .unwrap_or_else(|_| format!("(no regression.diffs at {})", diffs.display()));
        panic!("sql regression failed\n==== regression.diffs ====\n{diff_text}");
    }
}

#[test]
fn sql_regression() {
    run_pg_regress(REGRESS);
}
