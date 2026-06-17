import { useState, useEffect, useCallback } from 'react';
import {
  fetchAudiobooks,
  searchAudiobooks,
  fetchChapters,
  getHistory,
  removeFromHistory,
  getLikedBooks,
  toggleLikeBook,
  isBookLiked,
} from './api';
import Player from './Player';

const PAGE_SIZE = 12;

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
  const [player, setPlayer] = useState(null);
  const [loadingBook, setLoadingBook] = useState(false);

  const loadBooks = useCallback(async () => {
    setLoading(true);
    try {
      const data = await fetchAudiobooks(offset, PAGE_SIZE);
      setBooks(data);
    } catch (err) {
      console.error(err);
      setBooks([]);
    }
    setLoading(false);
    setSearching(false);
  }, [offset]);

  useEffect(() => {
    if (!searching) loadBooks();
  }, [loadBooks, searching]);

  useEffect(() => {
    setHistory(getHistory());
    setLikedBooks(getLikedBooks());
  }, []);

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
      const results = await searchAudiobooks(query.trim());
      setBooks(results);
    } catch (err) {
      console.error(err);
      setBooks([]);
    }
    setLoading(false);
  };

  const openBook = async (book, initialChapter = 0, initialPosition = 0) => {
    setLoadingBook(true);
    try {
      const chapters = await fetchChapters(book);
      if (chapters.length === 0) {
        alert('Failed to load audio tracks. This book may be restricted.');
        return;
      }
      setPlayer({ book, chapters, initialChapter, initialPosition: initialPosition / 1000 });
    } catch (err) {
      console.error(err);
      alert('Failed to load audiobook.');
    } finally {
      setLoadingBook(false);
    }
  };

  const resumeBook = (entry) => {
    openBook(entry.book, entry.chapterIndex, entry.positionMs);
  };

  const handleLikeToggle = (book) => {
    const updated = toggleLikeBook(book);
    setLikedBooks(updated);
  };

  const handleRemoveHistory = (audioBookId, e) => {
    e.stopPropagation();
    setHistory(removeFromHistory(audioBookId));
  };

  const displayBooks = showLiked ? likedBooks : books;
  const page = Math.floor(offset / PAGE_SIZE) + 1;

  return (
    <div className="app">
      <header className="header">
        <h1>Audiobooks</h1>
        <div className="header-actions">
          <button
            className={`icon-btn ${showLiked ? 'active' : ''}`}
            onClick={() => {
              setShowLiked(!showLiked);
              setSearching(false);
              setSearchQuery('');
              if (!showLiked) setLikedBooks(getLikedBooks());
            }}
            aria-label="Liked audiobooks"
            title="Liked"
          >
            {showLiked ? '❤️' : '🤍'}
          </button>
        </div>
      </header>

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
          {showLiked ? 'No liked audiobooks' : 'No audiobooks found'}
        </div>
      ) : (
        <div className="book-grid">
          {displayBooks.map((book) => (
            <BookCard
              key={book.audioBookId}
              book={book}
              onOpen={openBook}
              onLikeToggle={handleLikeToggle}
              liked={isBookLiked(book.audioBookId)}
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
        </div>
      )}

      {player && (
        <Player
          book={player.book}
          chapters={player.chapters}
          initialChapter={player.initialChapter}
          initialPosition={player.initialPosition}
          onClose={() => {
            setPlayer(null);
            setHistory(getHistory());
          }}
        />
      )}
    </div>
  );
}
