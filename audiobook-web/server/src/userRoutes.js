import { Router } from 'express';
import { authMiddleware } from './auth.js';
import {
  getHistory,
  upsertHistory,
  deleteHistory,
  getBookmarks,
  addBookmark,
  removeBookmark,
  isBookmarked,
} from './db.js';

const router = Router();

router.get('/history', authMiddleware, (req, res) => {
  res.json(getHistory(req.user.id));
});

router.put('/history', authMiddleware, (req, res) => {
  const { book, chapterIndex, positionMs } = req.body;
  if (!book?.audioBookId) {
    return res.status(400).json({ error: 'Book required' });
  }
  upsertHistory(req.user.id, book, chapterIndex ?? 0, positionMs ?? 0);
  res.json({ ok: true });
});

router.delete('/history/:audioBookId', authMiddleware, (req, res) => {
  deleteHistory(req.user.id, req.params.audioBookId);
  res.json({ ok: true });
});

router.get('/bookmarks', authMiddleware, (req, res) => {
  res.json(getBookmarks(req.user.id));
});

router.post('/bookmarks', authMiddleware, (req, res) => {
  const { book } = req.body;
  if (!book?.audioBookId) {
    return res.status(400).json({ error: 'Book required' });
  }
  addBookmark(req.user.id, book);
  res.json({ ok: true });
});

router.delete('/bookmarks/:audioBookId', authMiddleware, (req, res) => {
  removeBookmark(req.user.id, req.params.audioBookId);
  res.json({ ok: true });
});

router.get('/bookmarks/:audioBookId', authMiddleware, (req, res) => {
  res.json({ liked: isBookmarked(req.user.id, req.params.audioBookId) });
});

router.post('/sync', authMiddleware, (req, res) => {
  const { history = [], bookmarks = [] } = req.body;
  for (const entry of history) {
    if (entry.book?.audioBookId) {
      upsertHistory(
        req.user.id,
        entry.book,
        entry.chapterIndex ?? 0,
        entry.positionMs ?? 0
      );
    }
  }
  for (const book of bookmarks) {
    if (book?.audioBookId) addBookmark(req.user.id, book);
  }
  res.json({
    history: getHistory(req.user.id),
    bookmarks: getBookmarks(req.user.id),
  });
});

export default router;
