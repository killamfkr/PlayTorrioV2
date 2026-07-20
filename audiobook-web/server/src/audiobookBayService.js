import * as cheerio from 'cheerio';

const ABB_BASE = 'https://audiobookbay.lu';
const USER_AGENT =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36';

const AUDIO_EXT = /\.(m4b|mp3|m4a|aac|ogg|flac|wav)$/i;

async function fetchPage(url) {
  const response = await fetch(url, {
    headers: { 'User-Agent': USER_AGENT, Referer: ABB_BASE },
  });
  if (!response.ok) throw new Error(`ABB fetch failed: ${response.status}`);
  return response.text();
}

function slugFromUrl(url) {
  const path = url.replace(ABB_BASE, '').replace(/^\//, '');
  return path.replace(/^abss\//, '').replace(/\/$/, '');
}

function parseListingPost($, element) {
  const post = $(element);
  const titleLink = post.find('div.postTitle h2 a').first();
  const href = titleLink.attr('href') ?? '';
  if (!href.includes('/abss/')) return null;

  const title = titleLink.text().trim();
  const slug = slugFromUrl(href.startsWith('http') ? href : `${ABB_BASE}${href}`);
  const pageUrl = href.startsWith('http') ? href : `${ABB_BASE}${href}`;

  let coverImage = post.find('.postContent img').first().attr('src') ?? '';
  if (coverImage.startsWith('//')) coverImage = `https:${coverImage}`;
  coverImage = coverImage.replace(/\[\/img\]$/i, '').trim();

  const postInfo = post.find('.postInfo').text();
  let language = 'English';
  const langMatch = postInfo.match(/Language:\s*([^\n]+?)(?:\s*Keywords:|$)/);
  if (langMatch) language = langMatch[1].trim();

  return formatAbbBook({
    slug,
    title,
    pageUrl,
    coverImage,
    language,
  });
}

export function formatAbbBook({ slug, title, pageUrl, coverImage, language, magnetUri, audioSample }) {
  return {
    uuid: pageUrl,
    audioBookId: `abb_${slug}`,
    dynamicSlugId: slug,
    title,
    coverImage: coverImage ?? '',
    source: 'audiobookbay',
    pageUrl,
    language,
    magnetUri: magnetUri ?? null,
    audioSample: audioSample ?? null,
    thumbUrl: coverImage || `${ABB_BASE}/images/default_cover.jpg`,
  };
}

export async function browseAudiobookBay(page = 1) {
  const url = page <= 1 ? `${ABB_BASE}/` : `${ABB_BASE}/page/${page}/`;
  const html = await fetchPage(url);
  const $ = cheerio.load(html);
  const books = [];

  $('#content div.post').each((_, el) => {
    const book = parseListingPost($, el);
    if (book) books.push(book);
  });

  return books;
}

export async function searchAudiobookBay(query, page = 1) {
  const url =
    page <= 1
      ? `${ABB_BASE}/?s=${encodeURIComponent(query)}`
      : `${ABB_BASE}/page/${page}/?s=${encodeURIComponent(query)}`;
  const html = await fetchPage(url);
  const $ = cheerio.load(html);

  if ($('#content h3').text().trim() === 'Not Found') return [];

  const books = [];
  $('#content div.post').each((_, el) => {
    const book = parseListingPost($, el);
    if (book) books.push(book);
  });

  return books;
}

function buildMagnetUrl(hash, title, trackers) {
  if (!hash) return null;
  let magnet = `magnet:?xt=urn:btih:${hash}&dn=${encodeURIComponent(title)}`;
  for (const tr of trackers) {
    magnet += `&tr=${encodeURIComponent(tr)}`;
  }
  return magnet;
}

export async function parseAudiobookBayDetail(pageUrl) {
  const html = await fetchPage(pageUrl);
  const $ = cheerio.load(html);

  const title = $('h1[itemprop="name"]').text().trim() || $('.postTitle h1').text().trim();
  const slug = slugFromUrl(pageUrl);

  let coverImage = $('.postContent img[itemprop="image"]').attr('src') ?? '';
  if (!coverImage) coverImage = $('.postContent img').first().attr('src') ?? '';
  if (coverImage.startsWith('//')) coverImage = `https:${coverImage}`;
  coverImage = coverImage.replace(/\[\/img\]$/i, '').trim();

  let audioSample = $('audio').attr('src') ?? null;

  const trackers = [];
  let infoHash = '';

  $('.postContent table tr').each((_, row) => {
    const label = $(row).find('td').first().text().trim();
    const value = $(row).find('td').last().text().trim();

    if (label === 'Tracker:') trackers.push(value);
    if (label === 'Info Hash:') infoHash = value;
  });

  const fileNames = [];
  $('.postContent table tr').each((_, row) => {
    const cell = $(row).find('td[colspan="2"], td[colspan=\'2\']').text().trim();
    if (cell && AUDIO_EXT.test(cell)) {
      const name = cell.replace(/\s+[\d.]+\s*(KB|MB|GB)s?$/i, '').trim();
      if (name) fileNames.push(name);
    }
  });

  const magnetUri = buildMagnetUrl(infoHash, title, trackers);

  return {
    slug,
    title,
    pageUrl,
    coverImage,
    audioSample,
    infoHash,
    trackers,
    magnetUri,
    fileNames,
  };
}

export async function getAudiobookBayChapters(book, baseUrl) {
  const detail = await parseAudiobookBayDetail(book.pageUrl);

  if (!detail.magnetUri) {
    if (detail.audioSample) {
      return [
        {
          title: 'Preview Sample',
          url: `${baseUrl}/audio-proxy?url=${encodeURIComponent(detail.audioSample)}&referer=${encodeURIComponent(ABB_BASE)}`,
          headers: null,
        },
      ];
    }
    return [];
  }

  const { prepareTorrent, getTorrentFiles } = await import('./torrentStream.js');
  const bookId = book.audioBookId;

  let files;
  try {
    files = await prepareTorrent(bookId, detail.magnetUri, detail.trackers);
  } catch (err) {
    console.error('[ABB] Torrent prepare failed:', err.message);
    if (detail.audioSample) {
      return [
        {
          title: 'Preview Sample (full book unavailable)',
          url: `${baseUrl}/audio-proxy?url=${encodeURIComponent(detail.audioSample)}&referer=${encodeURIComponent(ABB_BASE)}`,
          headers: null,
        },
      ];
    }
    throw err;
  }

  const torrentFiles = getTorrentFiles(bookId);
  const names = files.length ? files : detail.fileNames;

  return torrentFiles.map((file, index) => ({
    title: names[index] || file.name || `Part ${index + 1}`,
    url: `${baseUrl}/abb-stream/${encodeURIComponent(bookId)}/${index}`,
    headers: null,
  }));
}
