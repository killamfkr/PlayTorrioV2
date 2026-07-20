import { useState, useEffect, useCallback } from 'react';
import {
  fetchAudiobooks,
  searchAudiobooks,
  fetchChapters,
  fetchVpnStatus,
  fetchMe,
  logout,
  getHistory,
  removeFromHistory,
  getLikedBooks,
  toggleLikeBook,
  isBookLiked,
} from './api';
import Player from './Player';
import AuthModal from './AuthModal';

const PAGE_SIZE = 12;

const SOURCES = [
  { id: 'tokybook', label: 'Tokybook' },
  { id: 'audiobookbay', label: 'AudioBookBay' },
];

function BookCard({ book, onOpen, onLikeToggle, liked }) {
  const coverUrl = book.thumbUrl || book.coverImage;

  return (
    <div className="book-card" onClick={() => onOpen(book)}>
      {coverUrl ? (
        <img
          className="cover"
          src={coverUrl}
          alt={book.title}
          loading="lazy"
          onError={(e) => {
            if (book.coverImage && e.target.src !== book.coverImage) {
              e.target.src = book.coverImage;
            } else {
              e.target.style.display = 'none';
              e.target.nextSibling?.classList.add('visible');
            }
          }}
        />
      ) : (
        <div className="cover-placeholder">📖</div>
      )}
      <div className="cover-placeholder" style={{ display: 'none' }}>
        📖
      </div>
      <p className="title">{book.title}</p>
      <button
        className="like-btn"
        onClick={(e) => {
          e.stopPropagation();
          onLikeToggle(book);
        }}
        aria-label={liked ? 'Unlike' : 'Like'}
      >
        {liked ? '❤️' : '🤍'}
      </button>
    </div>
  );
}

export default function App() {
  const [books, setBooks] = useState([]);
  const [likedBooks, setLikedBooks] = useState([]);
  const [history, setHistory] = useState([]);
  const [loading, setLoading] = useState(true);
  const [searching, setSearching] = useState(false);
  const [showLiked, setShowLiked] = useState(false);
  const [offset, setOffset] = useState(0);
  const [searchQuery, setSearchQuery] = useState('');
  const [source, setSource] = useState('tokybook');
  const [player, setPlayer] = useState(null);
  const [loadingBook, setLoadingBook] = useState(false);
  const [loadingMessage, setLoadingMessage] = useState('');
  const [vpn, setVpn] = useState(null);
  const [user, setUser] = useState(null);
  const [showAuth, setShowAuth] = useState(false);
  const [authChecked, setAuthChecked] = useState(false);

  const refreshUserData = useCallback(async () => {
    const [h, liked] = await Promise.all([getHistory(), getLikedBooks()]);
    setHistory(h);
    setLikedBooks(liked);
  }, []);

  const loadBooks = useCallback(async () => {
    setLoading(true);
    try {
      const data = await fetchAudiobooks(offset, PAGE_SIZE, source);
      setBooks(data);
    } catch (err) {
      console.error(err);
      setBooks([]);
    }
    setLoading(false);
    setSearching(false);
  }, [offset, source]);

  useEffect(() => {
    if (!searching) loadBooks();
  }, [loadBooks, searching]);

  useEffect(() => {
    Promise.all([fetchMe(), fetchVpnStatus()]).then(([u, v]) => {
      setUser(u);
      setVpn(v);
      setAuthChecked(true);
    });
    refreshUserData();
  }, [refreshUserData]);

  const handleSearch = async (query) => {
    setSearchQuery(query);
    if (!query.trim()) {
      setSearching(false);
      setOffset(0);
      return;
    }
    setSearching(true);
    setShowLiked(false);
    setLoading(true);
    try {
      const results = await searchAudiobooks(query.trim(), source === 'audiobookbay' ? 'audiobookbay' : 'all');
      setBooks(results);
    } catch (err) {
      console.error(err);
      setBooks([]);
    }
    setLoading(false);
  };

  const openBook = async (book, initialChapter = 0, initialPosition = 0) => {
    setLoadingBook(true);
    setLoadingMessage(
      book.source === 'audiobookbay'
        ? 'Connecting to torrent peers… this may take a minute'
        : 'Loading audiobook…'
    );
    try {
      const chapters = await fetchChapters(book);
      if (chapters.length === 0) {
        alert('Failed to load audio tracks. This book may be restricted or have no seeders.');
        return;
      }
      setPlayer({ book, chapters, initialChapter, initialPosition: initialPosition / 1000 });
    } catch (err) {
      console.error(err);
      alert(err.message || 'Failed to load audiobook.');
    } finally {
      setLoadingBook(false);
      setLoadingMessage('');
    }
  };

  const resumeBook = (entry) => {
    openBook(entry.book, entry.chapterIndex, entry.positionMs);
  };

  const handleLikeToggle = async (book) => {
    const updated = await toggleLikeBook(book);
    setLikedBooks(updated);
  };

  const handleRemoveHistory = async (audioBookId, e) => {
    e.stopPropagation();
    const updated = await removeFromHistory(audioBookId);
    setHistory(updated);
  };

  const handleLogout = async () => {
    await logout();
    setUser(null);
    await refreshUserData();
  };

  const handleAuthSuccess = async (u) => {
    setUser(u);
    await refreshUserData();
  };

  const displayBooks = showLiked ? likedBooks : books;
  const page = Math.floor(offset / PAGE_SIZE) + 1;

  if (!authChecked) {
    return (
      <div className="loading" style={{ minHeight: '100vh' }}>
        <div className="spinner" />
      </div>
    );
  }

  return (
    <div className="app">
      <header className="header">
        <h1>Audiobooks</h1>
        <div className="header-actions">
          {vpn?.enabled && (
            <span
              className="vpn-badge"
              title={vpn.publicIp ? `PIA VPN active — exit IP ${vpn.publicIp}` : 'PIA VPN active'}
            >
              🔒 PIA
            </span>
          )}
          {user ? (
            <div className="user-menu">
              <span className="user-name">{user.username}</span>
              <button className="auth-btn" onClick={handleLogout}>
                Log out
              </button>
            </div>
          ) : (
            <button className="auth-btn" onClick={() => setShowAuth(true)}>
              Sign in
            </button>
          )}
          <button
            className={`icon-btn ${showLiked ? 'active' : ''}`}
            onClick={async () => {
              setShowLiked(!showLiked);
              setSearching(false);
              setSearchQuery('');
              if (!showLiked) setLikedBooks(await getLikedBooks());
            }}
            aria-label="Bookmarked audiobooks"
            title="Bookmarks"
          >
            {showLiked ? '❤️' : '🤍'}
          </button>
        </div>
      </header>

      <div className="source-tabs">
        {SOURCES.map((s) => (
          <button
            key={s.id}
            className={`source-tab ${source === s.id ? 'active' : ''}`}
            onClick={() => {
              setSource(s.id);
              setSearching(false);
              setSearchQuery('');
              setOffset(0);
              setShowLiked(false);
            }}
          >
            {s.label}
          </button>
        ))}
      </div>

      <div className="search-bar">
        <div className="search-wrapper">
          <span className="search-icon">🔍</span>
          <input
            type="search"
            placeholder="Search audiobooks..."
            value={searchQuery}
            onChange={(e) => {
              const q = e.target.value;
              setSearchQuery(q);
              if (!q) handleSearch('');
            }}
            onKeyDown={(e) => e.key === 'Enter' && handleSearch(searchQuery)}
          />
        </div>
      </div>

      {!searching && history.length > 0 && (
        <section>
          <p className="section-title">CONTINUE LISTENING</p>
          <div className="history-carousel">
            {history.map((entry) => (
              <div
                key={entry.book.audioBookId}
                className="history-card"
                onClick={() => resumeBook(entry)}
              >
                <img
                  src={entry.book.thumbUrl || entry.book.coverImage}
                  alt=""
                  onError={(e) => {
                    e.target.style.display = 'none';
                  }}
                />
                <div className="info">
                  <p className="title">{entry.book.title}</p>
                  <p className="chapter">Chapter {entry.chapterIndex + 1}</p>
                </div>
                <span className="play-icon">▶</span>
                <button
                  className="remove-btn"
                  onClick={(e) => handleRemoveHistory(entry.book.audioBookId, e)}
                  aria-label="Remove from history"
                >
                  ✕
                </button>
              </div>
            ))}
          </div>
        </section>
      )}

      {loading ? (
        <div className="loading">
          <div className="spinner" />
        </div>
      ) : displayBooks.length === 0 ? (
        <div className="empty">
          {showLiked ? 'No bookmarked audiobooks' : 'No audiobooks found'}
        </div>
      ) : (
        <div className="book-grid">
          {displayBooks.map((book) => (
            <BookCard
              key={book.audioBookId}
              book={book}
              onOpen={openBook}
              onLikeToggle={handleLikeToggle}
              liked={isBookLiked(book.audioBookId, likedBooks)}
            />
          ))}
        </div>
      )}

      {!searching && !showLiked && (
        <div className="pagination">
          <button
            className="prev"
            disabled={offset === 0}
            onClick={() => setOffset(Math.max(0, offset - PAGE_SIZE))}
          >
            Previous
          </button>
          <span>Page {page}</span>
          <button className="next" onClick={() => setOffset(offset + PAGE_SIZE)}>
            Next Page
          </button>
        </div>
      )}

      {loadingBook && (
        <div className="modal-loading">
          <div className="spinner" />
          {loadingMessage && <p className="loading-message">{loadingMessage}</p>}
        </div>
      )}

      {showAuth && (
        <AuthModal onClose={() => setShowAuth(false)} onSuccess={handleAuthSuccess} />
      )}

      {player && (
        <Player
          book={player.book}
          chapters={player.chapters}
          initialChapter={player.initialChapter}
          initialPosition={player.initialPosition}
          onClose={async () => {
            setPlayer(null);
            await refreshUserData();
          }}
        />
      )}
    </div>
  );
}
