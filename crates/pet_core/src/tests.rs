use super::*;
use std::sync::atomic::{AtomicU64, Ordering};
static COUNTER: AtomicU64 = AtomicU64::new(0);
struct Save(String);
impl Save {
    fn new() -> Self {
        Self(
            std::env::temp_dir()
                .join(format!(
                    "alice-test-{}-{}.sqlite3",
                    std::process::id(),
                    COUNTER.fetch_add(1, Ordering::SeqCst)
                ))
                .to_string_lossy()
                .into_owned(),
        )
    }
    fn call(&self, request: Value, at: i64) -> Value {
        execute(&self.0, request, at).unwrap()
    }
    fn select(&self) {
        self.call(json!({"op":"select_persona","id":"gentle_resolute"}), 1000);
    }
}
impl Drop for Save {
    fn drop(&mut self) {
        let _ = std::fs::remove_file(&self.0);
    }
}

#[test]
fn arcade_scores_survive_restart_and_duplicate_results_are_idempotent() {
    let save = Save::new();
    save.select();
    let result = json!({"op":"arcade_result","game":"tetris","run_id":"first-run","score":1200});
    let first = save.call(result.clone(), 1000)["state"].clone();
    let duplicate = save.call(result, 1000)["state"].clone();
    assert_eq!(first, duplicate);
    save.call(
        json!({"op":"arcade_result","game":"tetris","run_id":"second-run","score":800}),
        1000,
    );
    let state = save.call(json!({"op":"snapshot"}), 1000)["state"].clone();
    assert_eq!(state["arcade"]["tetris"]["best"], 1200);
    assert_eq!(state["arcade"]["tetris"]["plays"], 2);
    assert!(execute(
        &save.0,
        json!({"op":"arcade_result","game":"tetris","run_id":"bad","score":-2}),
        1000
    )
    .is_err());
    assert!(execute(
        &save.0,
        json!({"op":"arcade_result","game":"unknown","run_id":"bad","score":0}),
        1000
    )
    .is_err());
    assert_eq!(state, save.call(json!({"op":"snapshot"}), 1000)["state"]);
}

#[test]
fn selection_is_explicit_and_save_survives_reopening() {
    let save = Save::new();
    let fresh = save.call(json!({"op":"snapshot"}), 1000);
    assert!(fresh["state"]["persona"].is_null());
    assert!(execute(&save.0, json!({"op":"action","action":"tea"}), 1000).is_err());
    save.select();
    save.call(json!({"op":"remember","content":"喜欢雨天"}), 1000);
    let reopened = save.call(json!({"op":"snapshot"}), 1001);
    assert_eq!(reopened["state"]["persona"], "gentle_resolute");
    assert_eq!(reopened["state"]["memories"][0]["content"], "喜欢雨天");
}

#[test]
fn switching_preserves_history_memory_and_progress() {
    let save = Save::new();
    save.select();
    save.call(json!({"op":"remember","content":"倾诉时先听我说"}), 1000);
    let before = save.call(json!({"op":"action","action":"tea"}), 1000)["state"].clone();
    let after = save.call(
        json!({"op":"select_persona","id":"reserved_attentive"}),
        1000,
    )["state"]
        .clone();
    for key in ["messages", "memories", "energy", "comfort", "created_at"] {
        assert_eq!(before[key], after[key], "{key}");
    }
    assert_eq!(after["persona"], "reserved_attentive");
}

#[test]
fn clock_changes_and_long_absence_are_bounded() {
    let save = Save::new();
    save.select();
    let future = save.call(json!({"op":"snapshot"}), 1000 + 86400 * 500)["state"].clone();
    assert_eq!(future["energy"], 30.0);
    assert!(future["comfort"].as_f64().unwrap() >= 35.0);
    let backwards = save.call(json!({"op":"snapshot"}), 999)["state"].clone();
    assert_eq!(backwards["last_tick"], future["last_tick"]);
    assert_eq!(backwards["energy"], future["energy"]);
}

#[test]
fn cooldown_and_game_results_are_applied_once() {
    let save = Save::new();
    save.select();
    let first = save.call(json!({"op":"action","action":"tea"}), 1000)["state"].clone();
    assert!(execute(&save.0, json!({"op":"action","action":"tea"}), 1001).is_err());
    let after = save.call(json!({"op":"snapshot"}), 1000)["state"].clone();
    assert_eq!(first, after);
    let game = save.call(json!({"op":"action","action":"start_game"}), 1000);
    assert_eq!(game["state"]["game"], "playing");
    assert!(!game.to_string().contains("target"));
    save.call(json!({"op":"action","action":"guess","guess":0}), 1000);
    assert!(execute(
        &save.0,
        json!({"op":"action","action":"guess","guess":0}),
        1000
    )
    .is_err());
}

#[test]
fn stale_responses_cannot_restore_forgotten_memory() {
    let save = Save::new();
    save.select();
    let added = save.call(json!({"op":"remember","content":"私人记忆青色雨伞"}), 1000);
    let id = added["state"]["memories"][0]["id"].clone();
    let prepared = save.call(json!({"op":"prepare_chat","text":"你记得什么？"}), 1000);
    assert!(prepared["request"].to_string().contains("私人记忆青色雨伞"));
    save.call(json!({"op":"commit_chat","text":"你记得什么？","answer":"私人记忆青色雨伞","revision":prepared["revision"]}),1000);
    let pending = save.call(json!({"op":"prepare_chat","text":"继续"}), 1000);
    save.call(json!({"op":"forget","id":id}), 1000);
    assert!(execute(
        &save.0,
        json!({"op":"commit_chat","text":"继续","answer":"旧回复","revision":pending["revision"]}),
        1000
    )
    .is_err());
    let next = save.call(json!({"op":"prepare_chat","text":"现在呢？"}), 1000);
    assert!(!next["request"].to_string().contains("私人记忆青色雨伞"));
    assert_eq!(next["state"]["messages"].as_array().unwrap().len(), 3);
}

#[test]
fn preparing_a_request_does_not_commit_failed_chat() {
    let save = Save::new();
    save.select();
    let before = save.call(json!({"op":"snapshot"}), 1000)["state"].clone();
    let prepared = save.call(json!({"op":"prepare_chat","text":"你好"}), 1000);
    assert_eq!(prepared["request"]["store"], false);
    assert_eq!(prepared["state"]["messages"], before["messages"]);
    assert!(!prepared["request"]
        .to_string()
        .contains("dialogue_examples"));
    assert!(execute(
        &save.0,
        json!({"op":"select_persona","id":"nonexistent"}),
        1000
    )
    .is_err());
    assert_eq!(
        save.call(json!({"op":"snapshot"}), 1000)["state"]["persona"],
        before["persona"]
    );
}

#[test]
fn future_schema_is_refused_without_overwriting_it() {
    let save = Save::new();
    save.select();
    let db = Db::open(&save.0).unwrap();
    db.run("PRAGMA user_version=99", None).unwrap();
    drop(db);
    assert!(execute(&save.0, json!({"op":"snapshot"}), 1000)
        .unwrap_err()
        .contains("更新版本"));
}

#[test]
fn care_migrates_old_saves_without_losing_memories_or_progress() {
    let save = Save::new();
    save.select();
    save.call(json!({"op":"remember","content":"喜欢海边"}), 1000);
    let mut old = save.call(json!({"op":"snapshot"}), 1000)["state"].clone();
    old["version"] = json!(1);
    for key in ["satiety", "cleanliness", "sleeping"] {
        old.as_object_mut().unwrap().remove(key);
    }
    let db = Db::open(&save.0).unwrap();
    db.run(
        "UPDATE companion SET data=?1 WHERE id=1",
        Some(&old.to_string()),
    )
    .unwrap();
    db.run("PRAGMA user_version=1", None).unwrap();
    drop(db);
    let migrated = save.call(json!({"op":"snapshot"}), 1000)["state"].clone();
    for key in [
        "memories", "messages", "energy", "comfort", "persona", "revision",
    ] {
        assert_eq!(old[key], migrated[key]);
    }
    assert_eq!(migrated["satiety"], 70.0);
    assert_eq!(migrated["sleeping"], false);
    assert_eq!(
        Db::open(&save.0)
            .unwrap()
            .run("PRAGMA user_version", None)
            .unwrap(),
        Some("2".into())
    );
}

#[test]
fn sleep_survives_restart_and_does_not_reward_repeated_toggles() {
    let save = Save::new();
    save.select();
    let start = save.call(json!({"op":"action","action":"rest"}), 1000)["state"].clone();
    assert_eq!(start["energy"], 80.0);
    let duplicate = save.call(json!({"op":"action","action":"rest"}), 1000)["state"].clone();
    assert_eq!(start, duplicate);
    assert!(execute(&save.0, json!({"op":"action","action":"feed"}), 1000).is_err());
    let hour = save.call(json!({"op":"snapshot"}), 4600)["state"].clone();
    assert_eq!(hour["sleeping"], true);
    assert_eq!(hour["energy"], 88.0);
    let wake = save.call(json!({"op":"action","action":"wake"}), 4600)["state"].clone();
    assert_eq!(wake["sleeping"], false);
    assert_eq!(wake["energy"], 88.0);
    assert_eq!(
        wake,
        save.call(json!({"op":"action","action":"wake"}), 4600)["state"]
    );
    let later = save.call(json!({"op":"snapshot"}), 8200)["state"].clone();
    assert_eq!(later["energy"], 86.5);
}

#[test]
fn feeding_bathing_cooldowns_and_absence_are_bounded() {
    let save = Save::new();
    save.select();
    let feed = save.call(json!({"op":"action","action":"feed"}), 1000)["state"].clone();
    assert_eq!(feed["satiety"], 95.0);
    assert!(execute(&save.0, json!({"op":"action","action":"feed"}), 1000).is_err());
    let bath = save.call(json!({"op":"action","action":"bath"}), 1000)["state"].clone();
    assert_eq!(bath["cleanliness"], 100.0);
    assert!(execute(&save.0, json!({"op":"action","action":"bath"}), 1001).is_err());
    let away = save.call(json!({"op":"snapshot"}), 1000 + 86400 * 365)["state"].clone();
    assert!(away["satiety"].as_f64().unwrap() >= 20.0);
    assert!(away["cleanliness"].as_f64().unwrap() >= 25.0);
    let backwards = save.call(json!({"op":"snapshot"}), 0)["state"].clone();
    for key in ["energy", "comfort", "satiety", "cleanliness"] {
        assert_eq!(away[key], backwards[key]);
    }
}
