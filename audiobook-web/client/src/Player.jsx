import { useState, useEffect, useRef, useCallback } from 'react';
import Hls from 'hls.js';
import { formatDuration, saveHistory } from './api';

export default function Player({ book, chapters, initialChapter = 0, initialPosition = 0, onClose }) {
  const audioRef = useRef(null);
  const hlsRef = useRef(null);
  const [chapterIndex, setChapterIndex] = useState(initialChapter);
  const [playing, setPlaying] = useState(false);
  const [buffering, setBuffering] = useState(false);
  const [currentTime, setCurrentTime] = useState(0);
  const [duration, setDuration] = useState(0);
  const [speed, setSpeed] = useState(1);
  const [autoplay, setAutoplay] = useState(true);
  const saveTimerRef = useRef(null);

  const saveProgress = useCallback(() => {
    if (!book || !audioRef.current) return;
    saveHistory({
      book,
      chapterIndex,
      positionMs: Math.floor(audioRef.current.currentTime * 1000),
      timestamp: Date.now(),
    });
  }, [book, chapterIndex]);

  const loadChapter = useCallback(
    (index, resumeAt = 0) => {
      const audio = audioRef.current;
      if (!audio || !chapters[index]) return;

      if (hlsRef.current) {
        hlsRef.current.destroy();
        hlsRef.current = null;
      }

      const url = chapters[index].url;
      setBuffering(true);

      if (url.includes('.m3u8') || url.includes('toky-proxy')) {
        if (Hls.isSupported()) {
          const hls = new Hls({ enableWorker: true });
          hlsRef.current = hls;
          hls.loadSource(url);
          hls.attachMedia(audio);
          hls.on(Hls.Events.MANIFEST_PARSED, () => {
            if (resumeAt > 0) audio.currentTime = resumeAt;
            audio.play().catch(() => {});
          });
          hls.on(Hls.Events.ERROR, (_, data) => {
            if (data.fatal) console.error('HLS error:', data);
          });
        } else if (audio.canPlayType('application/vnd.apple.mpegurl')) {
          audio.src = url;
          audio.addEventListener(
            'loadedmetadata',
            () => {
              if (resumeAt > 0) audio.currentTime = resumeAt;
              audio.play().catch(() => {});
            },
            { once: true }
          );
        }
      } else {
        audio.src = url;
        audio.addEventListener(
          'loadedmetadata',
          () => {
            if (resumeAt > 0) audio.currentTime = resumeAt;
            audio.play().catch(() => {});
          },
          { once: true }
        );
      }
    },
    [chapters]
  );

  useEffect(() => {
    loadChapter(initialChapter, initialPosition);
    return () => {
      if (hlsRef.current) hlsRef.current.destroy();
      saveProgress();
    };
  }, []);

  useEffect(() => {
    const audio = audioRef.current;
    if (!audio) return;

    const onTimeUpdate = () => setCurrentTime(audio.currentTime);
    const onDurationChange = () => setDuration(audio.duration || 0);
    const onPlay = () => setPlaying(true);
    const onPause = () => setPlaying(false);
    const onWaiting = () => setBuffering(true);
    const onCanPlay = () => setBuffering(false);
    const onEnded = () => {
      if (autoplay && chapterIndex < chapters.length - 1) {
        const next = chapterIndex + 1;
        setChapterIndex(next);
        loadChapter(next);
      }
    };

    audio.addEventListener('timeupdate', onTimeUpdate);
    audio.addEventListener('durationchange', onDurationChange);
    audio.addEventListener('play', onPlay);
    audio.addEventListener('pause', onPause);
    audio.addEventListener('waiting', onWaiting);
    audio.addEventListener('canplay', onCanPlay);
    audio.addEventListener('ended', onEnded);

    saveTimerRef.current = setInterval(saveProgress, 5000);

    if ('mediaSession' in navigator) {
      navigator.mediaSession.metadata = new MediaMetadata({
        title: book.title,
        artist: book.source ?? 'Audiobook',
        artwork: book.thumbUrl ? [{ src: book.thumbUrl }] : [],
      });
      navigator.mediaSession.setActionHandler('play', () => audio.play());
      navigator.mediaSession.setActionHandler('pause', () => audio.pause());
      navigator.mediaSession.setActionHandler('previoustrack', () => {
        if (chapterIndex > 0) changeChapter(chapterIndex - 1);
      });
      navigator.mediaSession.setActionHandler('nexttrack', () => {
        if (chapterIndex < chapters.length - 1) changeChapter(chapterIndex + 1);
      });
    }

    return () => {
      audio.removeEventListener('timeupdate', onTimeUpdate);
      audio.removeEventListener('durationchange', onDurationChange);
      audio.removeEventListener('play', onPlay);
      audio.removeEventListener('pause', onPause);
      audio.removeEventListener('waiting', onWaiting);
      audio.removeEventListener('canplay', onCanPlay);
      audio.removeEventListener('ended', onEnded);
      clearInterval(saveTimerRef.current);
    };
  }, [chapterIndex, autoplay, chapters.length, book, saveProgress]);

  const changeChapter = (index) => {
    setChapterIndex(index);
    loadChapter(index);
  };

  const togglePlay = () => {
    const audio = audioRef.current;
    if (!audio) return;
    if (audio.paused) audio.play();
    else audio.pause();
  };

  const handleSeek = (e) => {
    const audio = audioRef.current;
    if (!audio) return;
    audio.currentTime = parseFloat(e.target.value);
  };

  const handleClose = () => {
    saveProgress();
    onClose();
  };

  const coverUrl = book.thumbUrl || book.coverImage;

  return (
    <div className="player-overlay">
      <div className="player-bg">
        {coverUrl && <img src={coverUrl} alt="" />}
      </div>
      <div className="player-content">
        <div className="player-topbar">
          <button className="icon-btn" onClick={handleClose} aria-label="Close">
            ↓
          </button>
          <span className="label">AUDIOBOOK PLAYER</span>
          <div style={{ width: 44 }} />
        </div>

        <div className="player-cover">
          {coverUrl ? (
            <img src={coverUrl} alt={book.title} />
          ) : (
            <div className="cover-placeholder">📖</div>
          )}
        </div>

        <h2 className="player-title">{book.title}</h2>
        <p className="player-chapter-label">
          Chapter {chapterIndex + 1}: {chapters[chapterIndex]?.title}
        </p>

        <input
          type="range"
          className="progress-bar"
          min={0}
          max={duration || 1}
          step={0.1}
          value={currentTime}
          onChange={handleSeek}
        />
        <div className="time-row">
          <span>{formatDuration(currentTime)}</span>
          <span>{formatDuration(duration)}</span>
        </div>

        <div className="speed-row">
          <select
            value={speed}
            onChange={(e) => {
              const s = parseFloat(e.target.value);
              setSpeed(s);
              if (audioRef.current) audioRef.current.playbackRate = s;
            }}
          >
            {[0.5, 0.75, 1, 1.25, 1.5, 1.75, 2, 2.5, 3].map((s) => (
              <option key={s} value={s}>
                {s}x
              </option>
            ))}
          </select>
        </div>

        <div className="autoplay-row">
          <span>AUTOPLAY</span>
          <input
            type="checkbox"
            checked={autoplay}
            onChange={(e) => setAutoplay(e.target.checked)}
          />
        </div>

        <div className="player-controls">
          <button
            className="skip"
            disabled={chapterIndex === 0}
            onClick={() => changeChapter(chapterIndex - 1)}
            aria-label="Previous chapter"
          >
            ⏮
          </button>
          <button
            className="play-btn"
            onClick={togglePlay}
            disabled={buffering && !playing}
            aria-label={playing ? 'Pause' : 'Play'}
          >
            {buffering && !playing ? '…' : playing ? '⏸' : '▶'}
          </button>
          <button
            className="skip"
            disabled={chapterIndex >= chapters.length - 1}
            onClick={() => changeChapter(chapterIndex + 1)}
            aria-label="Next chapter"
          >
            ⏭
          </button>
        </div>

        <div className="chapter-list">
          <p className="section-title">CHAPTERS</p>
          {chapters.map((ch, i) => (
            <div
              key={i}
              className={`chapter-item ${i === chapterIndex ? 'active' : ''}`}
              onClick={() => changeChapter(i)}
            >
              <span className="num">{i + 1}</span>
              <span className="name">{ch.title}</span>
              {i === chapterIndex && <span>♫</span>}
            </div>
          ))}
        </div>
      </div>
      <audio ref={audioRef} preload="auto" />
    </div>
  );
}
