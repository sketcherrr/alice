//! Small SQLite boundary. All state writes are parameterized and transactional.
use std::ffi::{c_char, c_int, c_void, CStr, CString};
use std::ptr;

#[link(name = "sqlite3")]
extern "C" {
    fn sqlite3_open(filename: *const c_char, db: *mut *mut c_void) -> c_int;
    fn sqlite3_close(db: *mut c_void) -> c_int;
    fn sqlite3_busy_timeout(db: *mut c_void, ms: c_int) -> c_int;
    fn sqlite3_prepare_v2(
        db: *mut c_void,
        sql: *const c_char,
        n: c_int,
        stmt: *mut *mut c_void,
        tail: *mut *const c_char,
    ) -> c_int;
    fn sqlite3_bind_text(
        stmt: *mut c_void,
        index: c_int,
        text: *const c_char,
        n: c_int,
        destructor: Option<unsafe extern "C" fn(*mut c_void)>,
    ) -> c_int;
    fn sqlite3_step(stmt: *mut c_void) -> c_int;
    fn sqlite3_column_text(stmt: *mut c_void, index: c_int) -> *const u8;
    fn sqlite3_finalize(stmt: *mut c_void) -> c_int;
}

pub struct Db(*mut c_void);
struct Statement(*mut c_void);
impl Drop for Db {
    fn drop(&mut self) {
        unsafe {
            sqlite3_close(self.0);
        }
    }
}
impl Drop for Statement {
    fn drop(&mut self) {
        unsafe {
            sqlite3_finalize(self.0);
        }
    }
}

impl Db {
    pub fn open(path: &str) -> Result<Self, String> {
        let name = CString::new(path).map_err(|_| "存档路径无效")?;
        let mut ptr = ptr::null_mut();
        let status = unsafe { sqlite3_open(name.as_ptr(), &mut ptr) };
        let db = Self(ptr);
        if status != 0 {
            return Err("无法打开存档，请检查目录权限".into());
        }
        unsafe {
            sqlite3_busy_timeout(db.0, 5000);
        }
        let version = db.run("PRAGMA user_version", None)?.unwrap_or_default();
        if version != "0" && version != "1" && version != "2" {
            return Err("存档来自更新版本，请升级应用后打开".into());
        }
        db.run("PRAGMA synchronous=FULL", None)?;
        db.run("CREATE TABLE IF NOT EXISTS companion (id INTEGER PRIMARY KEY CHECK(id=1), data TEXT NOT NULL)", None)?;
        Ok(db)
    }
    pub fn run(&self, sql: &str, value: Option<&str>) -> Result<Option<String>, String> {
        let sql = CString::new(sql).map_err(|_| "查询格式错误")?;
        let mut stmt = ptr::null_mut();
        let code =
            unsafe { sqlite3_prepare_v2(self.0, sql.as_ptr(), -1, &mut stmt, ptr::null_mut()) };
        if code != 0 {
            return Err("存档查询失败".into());
        }
        // SQLITE_STATIC is safe here: bound data outlives step and finalize.
        let bound = value
            .map(CString::new)
            .transpose()
            .map_err(|_| "内容包含无效字符")?;
        let statement = Statement(stmt);
        if let Some(ref text) = bound {
            if unsafe { sqlite3_bind_text(statement.0, 1, text.as_ptr(), -1, None) } != 0 {
                return Err("存档写入失败".into());
            }
        }
        match unsafe { sqlite3_step(statement.0) } {
            100 => {
                let text = unsafe { sqlite3_column_text(statement.0, 0) };
                Ok(if text.is_null() {
                    None
                } else {
                    Some(
                        unsafe { CStr::from_ptr(text.cast()) }
                            .to_string_lossy()
                            .into_owned(),
                    )
                })
            }
            101 => Ok(None),
            _ => Err("存档操作失败，请稍后重试".into()),
        }
    }
}
