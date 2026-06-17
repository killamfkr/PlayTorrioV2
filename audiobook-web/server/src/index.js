import express from 'express';
import cors from 'cors';
import cookieParser from 'cookie-parser';
import path from 'path';
import { fileURLToPath } from 'url';
import { getAudiobooks, searchAudiobooks, getChapters } from './audiobookService.js';
import { handleTokyProxy, handleAudioProxy } from './proxy.js';
import { streamTorrentFile, getTorrentStatus } from './torrentStream.js';
import { optionalAuth } from './auth.js';
import authRoutes from './authRoutes.js';
import userRoutes from './userRoutes.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PORT = process.env.PORT || 3000;
const app = express();

app.use(cors({ origin: true, credentials: true }));
app.use(cookieParser());
app.use(express.json());
app.use(optionalAuth);

function getBaseUrl(req) {
  const proto = req.headers['x-forwarded-proto'] || req.protocol;
  const host = req.headers['x-forwarded-host'] || req.get('host');
  return `${proto}://${host}`;
}

app.get('/api/health', (_req, res) => {
  res.json({ status: 'ok' });
});

app.get('/api/vpn/status', async (_req, res) => {
  const enabled =
    process.env.VPN_ENABLED === '1' || process.env.VPN_ENABLED === 'true';
  const provider = process.env.VPN_PROVIDER ?? null;
  let publicIp = null;
  try {
    const r = await fetch('https://api.ipify.org?format=json', {
      signal: AbortSignal.timeout(5000),
    });
    if (r.ok) {
      const data = await r.json();
      publicIp = data.ip;
    }
  } catch {
    /* ignore */
  }
  res.json({ enabled, provider, publicIp });
});

app.get('/api/audiobooks', async (req, res) => {
  try {
    const offset = parseInt(req.query.offset ?? '0', 10);
    const limit = parseInt(req.query.limit ?? '12', 10);
    const source = req.query.source ?? 'tokybook';
    const books = await getAudiobooks(offset, limit, source);
    res.json(books);
  } catch (err) {
    console.error('[API] getAudiobooks:', err);
    res.json([]);
  }
});

app.get('/api/audiobooks/search', async (req, res) => {
  try {
    const query = req.query.q ?? '';
    const source = req.query.source ?? 'all';
    if (!query.trim()) {
      return res.json([]);
    }
    const books = await searchAudiobooks(query.trim(), source);
    res.json(books);
  } catch (err) {
    console.error('[API] search:', err);
    res.status(500).json({ error: err.message });
  }
});

app.post('/api/audiobooks/chapters', async (req, res) => {
  try {
    const book = req.body;
    if (!book?.audioBookId) {
      return res.status(400).json({ error: 'Book object required' });
    }
    const baseUrl = getBaseUrl(req);
    const chapters = await getChapters(book, baseUrl);
    res.json(chapters);
  } catch (err) {
    console.error('[API] chapters:', err);
    res.status(500).json({ error: err.message });
  }
});

app.get('/toky-proxy', async (req, res) => {
  const baseUrl = getBaseUrl(req);
  await handleTokyProxy(req, res, baseUrl);
});

app.get('/audio-proxy', handleAudioProxy);

app.get('/abb-stream/:bookId/:fileIndex', (req, res) => {
  streamTorrentFile(decodeURIComponent(req.params.bookId), parseInt(req.params.fileIndex, 10), req, res);
});

app.get('/api/abb/status/:bookId', (req, res) => {
  res.json(getTorrentStatus(decodeURIComponent(req.params.bookId)));
});

app.use('/api/auth', authRoutes);
app.use('/api/user', userRoutes);

const clientDist = path.join(__dirname, '../../client/dist');
app.use(express.static(clientDist));

app.get('*', (_req, res) => {
  res.sendFile(path.join(clientDist, 'index.html'));
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`PlayTorrio Audiobooks running on http://0.0.0.0:${PORT}`);
});
