const HISTORY_KEY = 'audiobook_history';
const LIKED_KEY = 'audiobook_liked';

export async function fetchAudiobooks(offset = 0, limit = 12) {
  const res = await fetch(`/api/audiobooks?offset=${offset}&limit=${limit}`);
  if (!res.ok) throw new Error('Failed to load audiobooks');
  return res.json();
}

export async function searchAudiobooks(query) {
  const res = await fetch(`/api/audiobooks/search?q=${encodeURIComponent(query)}`);
  if (!res.ok) throw new Error('Search failed');
  return res.json();
}

export async function fetchChapters(book) {
  const res = await fetch('/api/audiobooks/chapters', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(book),
  });
  if (!res.ok) throw new Error('Failed to load chapters');
  return res.json();
}

export function getHistory() {
  try {
    const raw = localStorage.getItem(HISTORY_KEY);
    return raw ? JSON.parse(raw) : [];
  } catch {
    return [];
  }
}

export function saveHistory(entry) {
  let history = getHistory();
  history = history.filter((h) => h.book.audioBookId !== entry.book.audioBookId);
  history.unshift(entry);
  if (history.length > 10) history = history.slice(0, 10);
  localStorage.setItem(HISTORY_KEY, JSON.stringify(history));
  return history;
}

export function removeFromHistory(audioBookId) {
  const history = getHistory().filter((h) => h.book.audioBookId !== audioBookId);
  localStorage.setItem(HISTORY_KEY, JSON.stringify(history));
  return history;
}

export function getLikedBooks() {
  try {
    const raw = localStorage.getItem(LIKED_KEY);
    return raw ? JSON.parse(raw) : [];
  } catch {
    return [];
  }
}

export function isBookLiked(audioBookId) {
  return getLikedBooks().some((b) => b.audioBookId === audioBookId);
}

export function toggleLikeBook(book) {
  let liked = getLikedBooks();
  const idx = liked.findIndex((b) => b.audioBookId === book.audioBookId);
  if (idx >= 0) {
    liked.splice(idx, 1);
  } else {
    liked.push(book);
  }
  localStorage.setItem(LIKED_KEY, JSON.stringify(liked));
  return liked;
}

export function formatDuration(seconds) {
  if (!seconds || seconds < 0) seconds = 0;
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  const s = Math.floor(seconds % 60);
  const mm = String(m).padStart(2, '0');
  const ss = String(s).padStart(2, '0');
  return h > 0 ? `${h}:${mm}:${ss}` : `${mm}:${ss}`;
}
