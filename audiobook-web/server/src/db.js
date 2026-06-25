import Database from 'better-sqlite3';
import fs from 'fs';
import path from 'path';

const DATA_DIR = process.env.DATA_DIR || path.join(process.cwd(), 'data');
const DB_PATH = path.join(DATA_DIR, 'audiobooks.db');

if (!fs.existsSync(DATA_DIR)) {
  fs.mkdirSync(DATA_DIR, { recursive: true });
}

const db = new Database(DB_PATH);
db.pragma('journal_mode = WAL');
db.pragma('foreign_keys = ON');

db.exec(`
  CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT NOT NULL UNIQUE COLLATE NOCASE,
    password_hash TEXT NOT NULL,
    created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
  );

  CREATE TABLE IF NOT EXISTS listening_history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    audio_book_id TEXT NOT NULL,
    book_json TEXT NOT NULL,
    chapter_index INTEGER NOT NULL DEFAULT 0,
    position_ms INTEGER NOT NULL DEFAULT 0,
    updated_at INTEGER NOT NULL,
    UNIQUE(user_id, audio_book_id)
  );

  CREATE TABLE IF NOT EXISTS bookmarks (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    audio_book_id TEXT NOT NULL,
    book_json TEXT NOT NULL,
    created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
    UNIQUE(user_id, audio_book_id)
  );

  CREATE INDEX IF NOT EXISTS idx_history_user ON listening_history(user_id, updated_at DESC);
  CREATE INDEX IF NOT EXISTS idx_bookmarks_user ON bookmarks(user_id, created_at DESC);
`);

export function createUser(username, passwordHash) {
  const stmt = db.prepare('INSERT INTO users (username, password_hash) VALUES (?, ?)');
  const result = stmt.run(username, passwordHash);
  return { id: result.lastInsertRowid, username };
}

export function getUserByUsername(username) {
  return db.prepare('SELECT * FROM users WHERE username = ? COLLATE NOCASE').get(username);
}

export function getUserById(id) {
  return db.prepare('SELECT id, username, created_at FROM users WHERE id = ?').get(id);
}

export function getHistory(userId, limit = 10) {
  const rows = db
    .prepare(
      `SELECT book_json, chapter_index, position_ms, updated_at
       FROM listening_history WHERE user_id = ?
       ORDER BY updated_at DESC LIMIT ?`
    )
    .all(userId, limit);

  return rows.map((row) => {
    const book = JSON.parse(row.book_json);
    return {
      book,
      chapterIndex: row.chapter_index,
      positionMs: row.position_ms,
      timestamp: row.updated_at * 1000,
    };
  });
}

export function upsertHistory(userId, book, chapterIndex, positionMs) {
  const now = Math.floor(Date.now() / 1000);
  db.prepare(
    `INSERT INTO listening_history (user_id, audio_book_id, book_json, chapter_index, position_ms, updated_at)
     VALUES (?, ?, ?, ?, ?, ?)
     ON CONFLICT(user_id, audio_book_id) DO UPDATE SET
       book_json = excluded.book_json,
       chapter_index = excluded.chapter_index,
       position_ms = excluded.position_ms,
       updated_at = excluded.updated_at`
  ).run(userId, book.audioBookId, JSON.stringify(book), chapterIndex, positionMs, now);
}

export function deleteHistory(userId, audioBookId) {
  db.prepare('DELETE FROM listening_history WHERE user_id = ? AND audio_book_id = ?').run(
    userId,
    audioBookId
  );
}

export function getBookmarks(userId) {
  const rows = db
    .prepare('SELECT book_json FROM bookmarks WHERE user_id = ? ORDER BY created_at DESC')
    .all(userId);
  return rows.map((row) => JSON.parse(row.book_json));
}

export function addBookmark(userId, book) {
  db.prepare(
    `INSERT OR IGNORE INTO bookmarks (user_id, audio_book_id, book_json) VALUES (?, ?, ?)`
  ).run(userId, book.audioBookId, JSON.stringify(book));
}

export function removeBookmark(userId, audioBookId) {
  db.prepare('DELETE FROM bookmarks WHERE user_id = ? AND audio_book_id = ?').run(
    userId,
    audioBookId
  );
}

export function isBookmarked(userId, audioBookId) {
  const row = db
    .prepare('SELECT 1 FROM bookmarks WHERE user_id = ? AND audio_book_id = ?')
    .get(userId, audioBookId);
  return !!row;
}

export default db;
