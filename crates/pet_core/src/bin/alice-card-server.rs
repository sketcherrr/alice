//! One SSH exec channel, newline-delimited JSON, no sockets or shell evaluation.
use serde_json::{json, Value};
use std::io::{self, BufRead, Write};
use std::path::PathBuf;

const LIMIT: usize = 1024;

fn failure(id: Value, code: &str, message: &str) -> Value {
    json!({"v":1,"id":id,"ok":false,"code":code,"message":message})
}

fn compact(state: &Value) -> Value {
    let mut out = json!({
        "persona":state["persona"], "sleeping":state["sleeping"],
        "revision":state["revision"], "game":state["game"]
    });
    for key in ["energy", "comfort", "satiety", "cleanliness"] {
        out[key] = json!(state[key].as_f64().unwrap_or(0.0).round() as u32);
    }
    out
}

fn handle(path: &str, input: &[u8], at: i64) -> Value {
    let request: Value = match serde_json::from_slice(input) {
        Ok(v) => v,
        Err(_) => return failure(Value::Null, "bad_json", "Invalid JSON."),
    };
    let id = request["id"].clone();
    if request["v"] != 1 || !id.as_u64().is_some_and(|n| n <= u32::MAX as u64) {
        return failure(
            Value::Null,
            "bad_protocol",
            "Use v=1 and an unsigned 32-bit id.",
        );
    }
    // Do not forward arbitrary core operations, timestamps, memory edits, or commands.
    let (core_request, message) = match request["op"].as_str().unwrap_or("") {
        "snapshot" => (json!({"op":"snapshot"}), "Welcome to your little island."),
        "persona" => {
            let persona = match request["choice"].as_u64() {
                Some(1) => "gentle_resolute",
                Some(2) => "clever_playful",
                Some(3) => "reserved_attentive",
                _ => return failure(id, "bad_persona", "Choose personality 1, 2 or 3."),
            };
            (
                json!({"op":"select_persona","id":persona}),
                "Nice to meet you!",
            )
        }
        "action" => {
            let action = request["action"].as_str().unwrap_or("");
            let message = match action {
                "feed" => "Nom nom. Thank you!",
                "bath" => "Bubbles make everything better.",
                "rest" => "Good night. See you in a little while.",
                "wake" => "Morning! I am right here.",
                "pet" => "Head pats received. Stay a little?",
                "tea" => "A tiny tea break, just for us.",
                "quiet" => "We can just sit here together.",
                "start_game" => "Find the pearl: press 1, 2 or 3.",
                "guess" => "Thanks for playing!",
                _ => return failure(id, "bad_action", "Unknown action."),
            };
            if action == "guess" && !request["guess"].as_u64().is_some_and(|n| n < 3) {
                return failure(id, "bad_guess", "Pick a shell: 1, 2 or 3.");
            }
            (
                json!({"op":"action","action":action,"guess":request["guess"]}),
                message,
            )
        }
        _ => return failure(id, "bad_operation", "Unknown operation."),
    };
    match alice_core::execute(path, core_request, at) {
        Ok(result) => {
            let game_result = match result["game_result"].as_str() {
                Some("找到珍珠啦！") => Some("win"),
                Some(_) => Some("miss"),
                None => None,
            };
            let message = match game_result {
                Some("win") => "You found the pearl!",
                Some(_) => "The pearl was in another shell.",
                None => message,
            };
            json!({"v":1,"id":id,"ok":true,"message":message,
                "state":compact(&result["state"]),"game_result":game_result})
        }
        Err(error) => {
            let (code, message) = match error.as_str() {
                "请先选择性格" => ("choose_persona", "First choose personality 1, 2 or 3."),
                "她还在睡觉，先轻轻叫醒她吧" => {
                    ("sleeping", "Still sleeping. Press W to wake.")
                }
                "肚子已经饱饱的啦，晚一点再吃吧" => {
                    ("full", "Full tummy. A snack later?")
                }
                "先享受这一小会儿，稍后再来吧" => {
                    ("cooldown", "Take a tiny break. Try in 30 seconds.")
                }
                "这一局还没结束，先选一个贝壳吧" => {
                    ("game_active", "Pick a shell first: 1, 2 or 3.")
                }
                "先开始一局找珍珠" => ("no_game", "Press G to start a pearl game."),
                _ => (
                    "core_error",
                    "Save unavailable. Check host permissions/version.",
                ),
            };
            let mut reply = failure(id, code, message);
            // A failed action did not commit. Refresh the authoritative view for the client.
            if let Ok(snapshot) = alice_core::execute(path, json!({"op":"snapshot"}), at) {
                reply["state"] = compact(&snapshot["state"]);
            }
            reply
        }
    }
}

fn run(path: &str, mut input: impl BufRead, mut output: impl Write) -> io::Result<()> {
    // take() bounds even an unterminated hostile input; stop rather than draining forever.
    loop {
        let mut line = Vec::new();
        let size =
            std::io::Read::take(&mut input, (LIMIT + 1) as u64).read_until(b'\n', &mut line)?;
        if size == 0 {
            return Ok(());
        }
        let reply = if size > LIMIT {
            failure(Value::Null, "too_large", "Request limit is 1024 bytes.")
        } else if line.last() != Some(&b'\n') {
            // A torn SSH write must never turn into a completed interaction.
            return Ok(());
        } else {
            handle(path, &line, alice_core::now())
        };
        serde_json::to_writer(&mut output, &reply)?;
        output.write_all(b"\n")?;
        output.flush()?;
        if size > LIMIT {
            return Ok(());
        }
    }
}

fn main() {
    let mut args = std::env::args().skip(1);
    let directory = match args.next().as_deref() {
        Some("--data-dir") => match args.next() {
            Some(value) if args.next().is_none() => PathBuf::from(value),
            _ => usage(),
        },
        None => match std::env::var_os("HOME") {
            Some(home) => PathBuf::from(home).join(".local/share/alice-cardputer"),
            None => {
                eprintln!("HOME missing; supply --data-dir.");
                std::process::exit(1);
            }
        },
        _ => usage(),
    };
    if let Err(error) = std::fs::create_dir_all(&directory) {
        eprintln!("Cannot create test save directory: {error}");
        std::process::exit(1);
    }
    let path = directory.join("companion.sqlite3");
    let Some(path) = path.to_str() else {
        eprintln!("Invalid save path.");
        std::process::exit(1);
    };
    if let Err(error) = run(path, io::stdin().lock(), io::stdout().lock()) {
        if error.kind() != io::ErrorKind::BrokenPipe {
            eprintln!("Card session ended: {error}");
            std::process::exit(1);
        }
    }
}

fn usage() -> ! {
    eprintln!(
        "alice-card-server [--data-dir DIRECTORY]\nJSONL over stdin/stdout; see docs/cardputer.md."
    );
    std::process::exit(2);
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicU64, Ordering};
    static SEQUENCE: AtomicU64 = AtomicU64::new(0);
    struct Save(PathBuf);
    impl Save {
        fn new() -> Self {
            let path = std::env::temp_dir().join(format!(
                "alice-card-{}-{}",
                std::process::id(),
                SEQUENCE.fetch_add(1, Ordering::Relaxed)
            ));
            std::fs::create_dir_all(&path).unwrap();
            Self(path)
        }
        fn call(&self, request: Value, at: i64) -> Value {
            handle(
                self.0.join("test.sqlite3").to_str().unwrap(),
                request.to_string().as_bytes(),
                at,
            )
        }
    }
    impl Drop for Save {
        fn drop(&mut self) {
            let _ = std::fs::remove_dir_all(&self.0);
        }
    }
    fn req(op: &str) -> Value {
        json!({"v":1,"id":7,"op":op})
    }

    #[test]
    fn protocol_rejects_unknown_and_sensitive_operations() {
        let save = Save::new();
        for op in [
            "remember",
            "forget",
            "clear_chat",
            "prepare_chat",
            "shell",
            "",
        ] {
            assert_eq!(save.call(req(op), 100)["code"], "bad_operation");
        }
        assert_eq!(
            save.call(json!({"op":"snapshot"}), 100)["code"],
            "bad_protocol"
        );
        assert_eq!(
            save.call(json!({"v":1,"id":4294967296u64,"op":"snapshot"}), 100)["ok"],
            false
        );
        assert_eq!(handle("unused", b"not json", 100)["code"], "bad_json");
    }

    #[test]
    fn care_reconnect_and_cooldown_use_real_core() {
        let save = Save::new();
        let action = |name: &str| json!({"v":1,"id":8,"op":"action","action":name});
        assert_eq!(save.call(action("feed"), 100)["code"], "choose_persona");
        assert_eq!(
            save.call(json!({"v":1,"id":1,"op":"persona","choice":2}), 100)["ok"],
            true
        );
        assert_eq!(save.call(action("pet"), 100)["state"]["comfort"], 73);
        assert_eq!(save.call(action("pet"), 101)["code"], "cooldown");
        assert_eq!(save.call(action("feed"), 100)["state"]["satiety"], 95);
        assert_eq!(save.call(action("bath"), 100)["state"]["cleanliness"], 100);
        assert_eq!(save.call(action("rest"), 100)["state"]["sleeping"], true);
        assert_eq!(save.call(action("bath"), 102)["code"], "sleeping");
        let restored = save.call(req("snapshot"), 3700);
        assert_eq!(restored["state"]["energy"], 88);
        assert_eq!(restored["state"]["sleeping"], true);
        assert_eq!(restored["state"]["persona"], "clever_playful");
        assert_eq!(save.call(action("wake"), 3700)["state"]["sleeping"], false);
    }

    #[test]
    fn compact_frames_do_not_disclose_memory_or_pearl() {
        let save = Save::new();
        save.call(json!({"v":1,"id":1,"op":"persona","choice":1}), 100);
        let response = save.call(
            json!({"v":1,"id":2,"op":"action","action":"start_game"}),
            100,
        );
        assert_eq!(response["state"]["game"], "playing");
        for field in ["target", "messages", "memories", "events"] {
            assert!(!response.to_string().contains(field));
        }
        assert!(response.to_string().len() < 1024);
        assert_eq!(
            save.call(
                json!({"v":1,"id":3,"op":"action","action":"guess","guess":3}),
                100
            )["code"],
            "bad_guess"
        );
        let guess = save.call(
            json!({"v":1,"id":4,"op":"action","action":"guess","guess":1}),
            100,
        );
        assert_eq!(guess["state"]["game"], "idle");
        assert!([json!("win"), json!("miss")].contains(&guess["game_result"]));
    }

    #[test]
    fn bounded_frames_and_torn_input_do_not_apply_actions() {
        let save = Save::new();
        let path = save.0.join("test.sqlite3");
        let mut out = Vec::new();
        let oversized = vec![b'x'; LIMIT + 1];
        run(path.to_str().unwrap(), oversized.as_slice(), &mut out).unwrap();
        assert_eq!(
            serde_json::from_slice::<Value>(&out).unwrap()["code"],
            "too_large"
        );
        out.clear();
        run(
            path.to_str().unwrap(),
            b"{\"v\":1,\"id\":1,\"op\":\"persona\",\"choice\":1}".as_slice(),
            &mut out,
        )
        .unwrap();
        assert!(out.is_empty());
        assert_eq!(
            save.call(req("snapshot"), 100)["state"]["persona"],
            Value::Null
        );
        run(
            path.to_str().unwrap(),
            b"oops\n{\"v\":1,\"id\":2,\"op\":\"snapshot\"}\n".as_slice(),
            &mut out,
        )
        .unwrap();
        assert_eq!(
            out.split(|b| *b == b'\n')
                .filter(|line| !line.is_empty())
                .count(),
            2
        );
    }
}
