const HISTORY_KEY = 'audiobook_history';
const LIKED_KEY = 'audiobook_liked';

const creds = { credentials: 'include' };

let authUser = null;

export function getAuthUser() {
  return authUser;
}

export function setAuthUser(user) {
  authUser = user;
}

export async function fetchMe() {
  try {
    const res = await fetch('/api/auth/me', creds);
    if (!res.ok) {
      authUser = null;
      return null;
    }
    const data = await res.json();
    authUser = data.user;
    return data.user;
  } catch {
    authUser = null;
    return null;
  }
}

export async function login(username, password) {
  const res = await fetch('/api/auth/login', {
    method: 'POST',
    ...creds,
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ username, password }),
  });
  const data = await res.json();
  if (!res.ok) throw new Error(data.error || 'Login failed');
  authUser = data.user;
  await syncGuestData();
  return data.user;
}

export async function register(username, password) {
  const res = await fetch('/api/auth/register', {
    method: 'POST',
    ...creds,
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ username, password }),
  });
  const data = await res.json();
  if (!res.ok) throw new Error(data.error || 'Registration failed');
  authUser = data.user;
  await syncGuestData();
  return data.user;
}

export async function logout() {
  await fetch('/api/auth/logout', { method: 'POST', ...creds });
  authUser = null;
}

async function syncGuestData() {
  const history = getLocalHistory();
  const bookmarks = getLocalLikedBooks();
  if (history.length === 0 && bookmarks.length === 0) return;

  try {
    await fetch('/api/user/sync', {
      method: 'POST',
      ...creds,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ history, bookmarks }),
    });
    localStorage.removeItem(HISTORY_KEY);
    localStorage.removeItem(LIKED_KEY);
  } catch {
    /* keep local data if sync fails */
  }
}

export async function fetchAudiobooks(offset = 0, limit = 12, source = 'tokybook') {
  const res = await fetch(`/api/audiobooks?offset=${offset}&limit=${limit}&source=${source}`);
  if (!res.ok) throw new Error('Failed to load audiobooks');
  return res.json();
}

export async function searchAudiobooks(query, source = 'all') {
  const res = await fetch(
    `/api/audiobooks/search?q=${encodeURIComponent(query)}&source=${source}`
  );
  if (!res.ok) throw new Error('Search failed');
  return res.json();
}

export async function fetchVpnStatus() {
  try {
    const res = await fetch('/api/vpn/status');
    if (!res.ok) return { enabled: false };
    return res.json();
  } catch {
    return { enabled: false };
  }
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

function getLocalHistory() {
  try {
    const raw = localStorage.getItem(HISTORY_KEY);
    return raw ? JSON.parse(raw) : [];
  } catch {
    return [];
  }
}

export async function getHistory() {
  if (authUser) {
    try {
      const res = await fetch('/api/user/history', creds);
      if (res.ok) return res.json();
    } catch {
      /* fall through */
    }
  }
  return getLocalHistory();
}

export async function saveHistory(entry) {
  if (authUser) {
    try {
      await fetch('/api/user/history', {
        method: 'PUT',
        ...creds,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          book: entry.book,
          chapterIndex: entry.chapterIndex,
          positionMs: entry.positionMs,
        }),
      });
      return;
    } catch {
      /* fall through */
    }
  }
  let history = getLocalHistory();
  history = history.filter((h) => h.book.audioBookId !== entry.book.audioBookId);
  history.unshift(entry);
  if (history.length > 10) history = history.slice(0, 10);
  localStorage.setItem(HISTORY_KEY, JSON.stringify(history));
}

export async function removeFromHistory(audioBookId) {
  if (authUser) {
    try {
      await fetch(`/api/user/history/${encodeURIComponent(audioBookId)}`, {
        method: 'DELETE',
        ...creds,
      });
      return getHistory();
    } catch {
      /* fall through */
    }
  }
  const history = getLocalHistory().filter((h) => h.book.audioBookId !== audioBookId);
  localStorage.setItem(HISTORY_KEY, JSON.stringify(history));
  return history;
}

function getLocalLikedBooks() {
  try {
    const raw = localStorage.getItem(LIKED_KEY);
    return raw ? JSON.parse(raw) : [];
  } catch {
    return [];
  }
}

export async function getLikedBooks() {
  if (authUser) {
    try {
      const res = await fetch('/api/user/bookmarks', creds);
      if (res.ok) return res.json();
    } catch {
      /* fall through */
    }
  }
  return getLocalLikedBooks();
}

export function isBookLiked(audioBookId, likedBooks) {
  const list = likedBooks ?? getLocalLikedBooks();
  return list.some((b) => b.audioBookId === audioBookId);
}

export async function toggleLikeBook(book) {
  if (authUser) {
    const liked = await getLikedBooks();
    const isLiked = liked.some((b) => b.audioBookId === book.audioBookId);
    const url = `/api/user/bookmarks/${encodeURIComponent(book.audioBookId)}`;
    if (isLiked) {
      await fetch(url, { method: 'DELETE', ...creds });
    } else {
      await fetch('/api/user/bookmarks', {
        method: 'POST',
        ...creds,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ book }),
      });
    }
    return getLikedBooks();
  }
  let liked = getLocalLikedBooks();
  const idx = liked.findIndex((b) => b.audioBookId === book.audioBookId);
  if (idx >= 0) liked.splice(idx, 1);
  else liked.push(book);
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
