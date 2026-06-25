import WebTorrent from 'webtorrent';

const client = new WebTorrent({ maxConns: 55 });
const sessions = new Map();

const PREPARE_TIMEOUT_MS = 120000;

function getAudioFiles(torrent) {
  return torrent.files.filter((f) => /\.(m4b|mp3|m4a|aac|ogg|flac|wav)$/i.test(f.name));
}

export function prepareTorrent(bookId, magnetUri, trackers = []) {
  const existing = sessions.get(bookId);
  if (existing?.ready) {
    return Promise.resolve(existing.files.map((f) => f.name));
  }
  if (existing?.promise) return existing.promise;

  const promise = new Promise((resolve, reject) => {
    const torrent = client.add(magnetUri, { announce: trackers });

    const timeout = setTimeout(() => {
      reject(new Error('Torrent metadata timeout — try again later'));
    }, PREPARE_TIMEOUT_MS);

    torrent.on('error', (err) => {
      clearTimeout(timeout);
      sessions.delete(bookId);
      reject(err);
    });

    torrent.on('ready', () => {
      clearTimeout(timeout);
      const audioFiles = getAudioFiles(torrent);
      if (audioFiles.length === 0) {
        sessions.delete(bookId);
        reject(new Error('No audio files found in torrent'));
        return;
      }
      audioFiles.sort((a, b) => a.name.localeCompare(b.name, undefined, { numeric: true }));
      sessions.set(bookId, { torrent, files: audioFiles, ready: true });
      resolve(audioFiles.map((f) => f.name));
    });
  });

  sessions.set(bookId, { promise, ready: false });
  return promise;
}

export function getTorrentFiles(bookId) {
  return sessions.get(bookId)?.files ?? [];
}

export function getTorrentStatus(bookId) {
  const session = sessions.get(bookId);
  if (!session) return { status: 'not_found' };
  if (!session.ready) return { status: 'loading' };
  const torrent = session.torrent;
  return {
    status: 'ready',
    progress: torrent.progress,
    downloadSpeed: torrent.downloadSpeed,
    numPeers: torrent.numPeers,
    files: session.files.map((f) => f.name),
  };
}

function mimeForFile(name) {
  const ext = name.split('.').pop()?.toLowerCase();
  const map = {
    m4b: 'audio/mp4',
    m4a: 'audio/mp4',
    mp3: 'audio/mpeg',
    aac: 'audio/aac',
    ogg: 'audio/ogg',
    flac: 'audio/flac',
    wav: 'audio/wav',
  };
  return map[ext] ?? 'application/octet-stream';
}

export function streamTorrentFile(bookId, fileIndex, req, res) {
  const session = sessions.get(bookId);
  if (!session?.ready) {
    return res.status(503).json({ error: 'Torrent not ready yet' });
  }

  const file = session.files[fileIndex];
  if (!file) {
    return res.status(404).json({ error: 'File not found' });
  }

  const range = req.headers.range;
  const fileSize = file.length;

  if (range) {
    const parts = range.replace(/bytes=/, '').split('-');
    const start = parseInt(parts[0], 10);
    const end = parts[1] ? parseInt(parts[1], 10) : fileSize - 1;
    const chunkSize = end - start + 1;

    res.writeHead(206, {
      'Content-Range': `bytes ${start}-${end}/${fileSize}`,
      'Accept-Ranges': 'bytes',
      'Content-Length': chunkSize,
      'Content-Type': mimeForFile(file.name),
      'Access-Control-Allow-Origin': '*',
    });
    file.createReadStream({ start, end }).pipe(res);
  } else {
    res.writeHead(200, {
      'Content-Length': fileSize,
      'Content-Type': mimeForFile(file.name),
      'Accept-Ranges': 'bytes',
      'Access-Control-Allow-Origin': '*',
    });
    file.createReadStream().pipe(res);
  }
}

export function destroyTorrent(bookId) {
  const session = sessions.get(bookId);
  if (session?.torrent) {
    client.remove(session.torrent);
  }
  sessions.delete(bookId);
}

// Clean up idle torrents after 2 hours
setInterval(() => {
  for (const [bookId, session] of sessions.entries()) {
    if (session.ready && session.torrent && !session.torrent.done && session.torrent.numPeers === 0) {
      const idle = Date.now() - (session.lastAccess ?? Date.now());
      if (idle > 2 * 60 * 60 * 1000) destroyTorrent(bookId);
    }
  }
}, 30 * 60 * 1000);
