import * as cheerio from 'cheerio';

const TOKY_BASE = 'https://tokybook.com/api/v1';
const USER_AGENT =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36';

function getUserIdentity() {
  return {
    ipAddress: '',
    userAgent: USER_AGENT,
    timestamp: new Date().toISOString(),
  };
}

function getHeaders() {
  return {
    'Content-Type': 'application/json',
    Accept: 'application/json',
    Origin: 'https://tokybook.com',
    Referer: 'https://tokybook.com/',
    'User-Agent': USER_AGENT,
  };
}

function cleanTitle(title) {
  return title
    .replace(/\[Listen\]/gi, '')
    .replace(/\[Download\]/gi, '')
    .replace(/Audiobook/gi, '')
    .replace(/Online/gi, '')
    .split('–')
    .pop()
    .split('-')
    .pop()
    .trim();
}

function normalizeTitle(title) {
  return cleanTitle(title)
    .toLowerCase()
    .replace(/[^a-z0-9]/g, '');
}

function relevanceScore(title, query) {
  const titleLower = title.toLowerCase();
  if (titleLower === query) return 0;
  if (titleLower.startsWith(query)) return 1;
  if (titleLower.includes(query)) return 2;
  const queryWords = query.split(/\s+/);
  const matches = queryWords.filter((w) => titleLower.includes(w)).length;
  if (matches === queryWords.length) return 3;
  return 4 + (queryWords.length - matches);
}

function thumbUrl(book) {
  if (['audiozaic', 'goldenaudiobook', 'appaudiobooks'].includes(book.source)) {
    return book.coverImage;
  }
  return `https://tokybook.com/images/${book.audioBookId}`;
}

export function formatBook(book) {
  return { ...book, thumbUrl: thumbUrl(book) };
}

export async function getAudiobooks(offset = 0, limit = 12) {
  const payload = {
    offset,
    limit,
    typeFilter: 'audiobook',
    slugIdFilter: null,
    userIdentity: getUserIdentity(),
  };

  const response = await fetch(`${TOKY_BASE}/search/audiobooks`, {
    method: 'POST',
    headers: getHeaders(),
    body: JSON.stringify(payload),
  });

  if (!response.ok) return [];

  const data = await response.json();
  const items = data.content ?? [];
  return items.map((json) => formatBook(fromTokyJson(json)));
}

function fromTokyJson(json) {
  const source = json.source ?? 'tokybook';
  const uuid = json.uuid ?? '';
  return {
    uuid,
    audioBookId: json.audioBookId ?? '',
    dynamicSlugId: json.dynamicSlugId ?? '',
    title: json.title ?? '',
    coverImage: json.coverImage ?? '',
    source,
    pageUrl:
      json.pageUrl ??
      (source === 'audiozaic' || source === 'goldenaudiobook' ? uuid : null),
  };
}

async function searchTokybook(query) {
  const payload = {
    query,
    offset: 0,
    limit: 20,
    userIdentity: getUserIdentity(),
  };

  const response = await fetch(`${TOKY_BASE}/search/instant`, {
    method: 'POST',
    headers: getHeaders(),
    body: JSON.stringify(payload),
  });

  if (!response.ok) return [];

  const data = await response.json();
  return (data.content ?? []).map((json) => formatBook(fromTokyJson(json)));
}

async function searchAudiozaic(query) {
  const searchUrl = `https://audiozaic.com/?s=${encodeURIComponent(query)}`;
  const response = await fetch(searchUrl, {
    headers: { 'User-Agent': USER_AGENT },
  });
  if (!response.ok) return [];

  const html = await response.text();
  const $ = cheerio.load(html);
  const results = [];

  $('article.vce-post').each((_, article) => {
    const titleElement = $(article).find('h2.entry-title a');
    const pageUrl = titleElement.attr('href') ?? '';
    const title = cleanTitle(titleElement.text() ?? '');

    const imgElement = $(article).find('div.meta-image img');
    let coverUrl = imgElement.attr('data-src') ?? imgElement.attr('src') ?? '';

    if (coverUrl.includes('-') && coverUrl.includes('x')) {
      coverUrl = coverUrl.replace(/-\d+x\d+\.(jpg|jpeg|png|webp)/, '.$1');
    }

    if (!pageUrl) return;

    const uri = new URL(pageUrl);
    const pathSegments = uri.pathname.split('/').filter(Boolean);
    const slug = pathSegments.length ? pathSegments[pathSegments.length - 1] : String(pageUrl.length);

    results.push(
      formatBook({
        uuid: pageUrl,
        audioBookId: `az_${slug}`,
        dynamicSlugId: pageUrl,
        title,
        coverImage: coverUrl,
        source: 'audiozaic',
        pageUrl,
      })
    );
  });

  return results;
}

async function searchGoldenAudiobook(query) {
  const searchUrl = `https://goldenaudiobook.net/?s=${encodeURIComponent(query)}`;
  const response = await fetch(searchUrl, {
    headers: { 'User-Agent': USER_AGENT },
  });
  if (!response.ok) return [];

  const html = await response.text();
  const $ = cheerio.load(html);
  const results = [];

  $('li.ilovewp-post').each((_, article) => {
    const titleElement = $(article).find('h2.title-post a');
    const pageUrl = titleElement.attr('href') ?? '';
    const title = cleanTitle(titleElement.text() ?? '');

    const imgElement = $(article).find('div.post-cover img');
    let coverUrl = imgElement.attr('data-src') ?? imgElement.attr('src') ?? '';

    if (coverUrl.includes('-') && coverUrl.includes('x')) {
      coverUrl = coverUrl.replace(/-\d+x\d+\.(jpg|jpeg|png|webp)/, '.$1');
    }

    if (!pageUrl) return;

    const uri = new URL(pageUrl);
    const pathSegments = uri.pathname.split('/').filter(Boolean);
    const slug = pathSegments.length ? pathSegments[pathSegments.length - 1] : String(pageUrl.length);

    results.push(
      formatBook({
        uuid: pageUrl,
        audioBookId: `ga_${slug}`,
        dynamicSlugId: pageUrl,
        title,
        coverImage: coverUrl,
        source: 'goldenaudiobook',
        pageUrl,
      })
    );
  });

  return results;
}

async function fetchAppAudiobookCover(pageUrl) {
  try {
    const res = await fetch(pageUrl, { headers: { 'User-Agent': USER_AGENT } });
    if (!res.ok) return '';
    const html = await res.text();
    const $ = cheerio.load(html);
    const img = $('.wp-caption img').first().length
      ? $('.wp-caption img').first()
      : $('.entry img').first();
    return img.attr('src') ?? '';
  } catch {
    return '';
  }
}

async function searchAppAudiobooks(query) {
  const searchUrl =
    `https://appaudiobooks.net/wp-admin/admin-ajax.php` +
    `?s=${encodeURIComponent(query)}` +
    `&action=searchwp_live_search` +
    `&swpengine=default` +
    `&swpquery=${encodeURIComponent(query)}` +
    `&origin_id=0`;

  const response = await fetch(searchUrl, {
    headers: {
      'User-Agent': USER_AGENT,
      Referer: 'https://appaudiobooks.net/',
    },
  });
  if (!response.ok) return [];

  const html = await response.text();
  const $ = cheerio.load(html);
  const results = [];
  const seen = new Set();

  $('a[href]').each((_, link) => {
    const pageUrl = $(link).attr('href') ?? '';
    if (!pageUrl || !pageUrl.includes('appaudiobooks.net')) return;
    if (seen.has(pageUrl)) return;
    seen.add(pageUrl);

    const title = cleanTitle($(link).text().trim());
    if (!title) return;

    const uri = new URL(pageUrl);
    const pathSegments = uri.pathname.split('/').filter(Boolean);
    const slug = pathSegments.length ? pathSegments[pathSegments.length - 1] : String(pageUrl.length);

    results.push({
      uuid: pageUrl,
      audioBookId: `aab_${slug}`,
      dynamicSlugId: pageUrl,
      title,
      coverImage: '',
      source: 'appaudiobooks',
      pageUrl,
    });
  });

  const withCovers = await Promise.all(
    results.map(async (book) => {
      const cover = await fetchAppAudiobookCover(book.pageUrl);
      return formatBook(cover ? { ...book, coverImage: cover } : book);
    })
  );

  return withCovers;
}

export async function searchAudiobooks(query) {
  const [goldenResults, appAudioResults, tokyResults, audiozaicResults] = await Promise.all([
    searchGoldenAudiobook(query),
    searchAppAudiobooks(query),
    searchTokybook(query),
    searchAudiozaic(query),
  ]);

  const uniqueBooks = new Map();

  for (const book of goldenResults) {
    const key = normalizeTitle(book.title);
    if (key) uniqueBooks.set(key, book);
  }
  for (const book of appAudioResults) {
    const key = normalizeTitle(book.title);
    if (key && !uniqueBooks.has(key)) uniqueBooks.set(key, book);
  }
  for (const book of tokyResults) {
    const key = normalizeTitle(book.title);
    if (key && !uniqueBooks.has(key)) uniqueBooks.set(key, book);
  }
  for (const book of audiozaicResults) {
    const key = normalizeTitle(book.title);
    if (key && !uniqueBooks.has(key)) uniqueBooks.set(key, book);
  }

  const queryNorm = query.toLowerCase().trim();
  const bookList = Array.from(uniqueBooks.values());
  bookList.sort(
    (a, b) => relevanceScore(a.title, queryNorm) - relevanceScore(b.title, queryNorm)
  );
  return bookList;
}

function buildTokyProxyUrl(baseUrl, url, id, token, src) {
  return `${baseUrl}/toky-proxy?url=${encodeURIComponent(url)}&id=${encodeURIComponent(id)}&token=${encodeURIComponent(token)}&src=${encodeURIComponent(src)}`;
}

function buildAudioProxyUrl(baseUrl, url, referer) {
  return `${baseUrl}/audio-proxy?url=${encodeURIComponent(url)}&referer=${encodeURIComponent(referer ?? '')}`;
}

async function getTokyChapters(book, baseUrl) {
  const detailsPayload = {
    dynamicSlugId: book.dynamicSlugId,
    userIdentity: getUserIdentity(),
  };

  const detailsRes = await fetch(`${TOKY_BASE}/search/post-details`, {
    method: 'POST',
    headers: getHeaders(),
    body: JSON.stringify(detailsPayload),
  });
  if (!detailsRes.ok) return [];

  const detailsData = await detailsRes.json();
  const token = detailsData.postDetailToken;
  if (!token) return [];

  const playlistPayload = {
    audioBookId: book.audioBookId,
    postDetailToken: token,
    userIdentity: getUserIdentity(),
  };

  const playlistRes = await fetch(`${TOKY_BASE}/playlist`, {
    method: 'POST',
    headers: getHeaders(),
    body: JSON.stringify(playlistPayload),
  });
  if (!playlistRes.ok) return [];

  const data = await playlistRes.json();
  const streamToken = data.streamToken ?? '';
  const tracks = data.tracks ?? [];
  const baseAudioUrl = 'https://tokybook.com/api/v1/public/audio/';

  return tracks.map((t) => {
    const src = t.src ?? '';
    const title = t.trackTitle ?? 'Track';
    const encodedSrc = src.split('/').map((p) => encodeURIComponent(p)).join('/');
    const fullTrackSrc = `/api/v1/public/audio/${encodedSrc}`;
    const finalUrl = `${baseAudioUrl}${src}`;
    const proxiedUrl = buildTokyProxyUrl(
      baseUrl,
      finalUrl,
      book.audioBookId,
      streamToken,
      fullTrackSrc
    );
    return { title, url: proxiedUrl, headers: null };
  });
}

async function getGoldenChapters(book, baseUrl) {
  if (!book.pageUrl) return [];

  const pageRes = await fetch(book.pageUrl, {
    headers: { 'User-Agent': USER_AGENT },
  });
  if (!pageRes.ok) return [];

  const html = await pageRes.text();
  const $ = cheerio.load(html);
  const chapters = [];

  $('audio.wp-audio-shortcode').each((i, audio) => {
    const streamUrl = $(audio).find('source').attr('src') ?? '';
    if (streamUrl) {
      chapters.push({
        title: `Part ${i + 1}`,
        url: buildAudioProxyUrl(baseUrl, streamUrl, book.pageUrl),
        headers: null,
      });
    }
  });

  return chapters;
}

async function getAudiozaicChapters(book, baseUrl) {
  if (!book.pageUrl) return [];

  const pageRes = await fetch(book.pageUrl, {
    headers: { 'User-Agent': USER_AGENT },
  });
  if (!pageRes.ok) return [];

  const html = await pageRes.text();
  const $ = cheerio.load(html);

  const listenBtn = $('#listen-button');
  const onclick = listenBtn.attr('onclick') ?? '';
  const urlMatch = onclick.match(/window\.open\('([^']+)'/);
  let listenUrl = urlMatch?.[1];
  if (!listenUrl) return [];

  if (listenUrl.startsWith('/')) {
    listenUrl = `https://audiozaic.com${listenUrl}`;
  } else if (!listenUrl.startsWith('http')) {
    listenUrl = `https://audiozaic.com/${listenUrl}`;
  }

  const audioPageRes = await fetch(listenUrl, {
    headers: {
      'User-Agent': USER_AGENT,
      Referer: book.pageUrl,
    },
  });
  if (!audioPageRes.ok) return [];

  const audioHtml = await audioPageRes.text();
  const audioDoc = cheerio.load(audioHtml);
  const chapters = [];

  audioDoc('div.track').each((_, track) => {
    const title = audioDoc(track).find('span.songtitle').text() || 'Part';
    let streamUrl = audioDoc(track).find('audio source').attr('src') ?? '';
    if (!streamUrl) {
      streamUrl = audioDoc(track).find('div.albumtrack a').attr('href') ?? '';
    }
    if (streamUrl) {
      chapters.push({
        title,
        url: buildAudioProxyUrl(baseUrl, streamUrl, 'https://audiozaic.com/'),
        headers: null,
      });
    }
  });

  return chapters;
}

async function getAppAudiobooksChapters(book, baseUrl) {
  if (!book.pageUrl) return [];

  const pageRes = await fetch(book.pageUrl, {
    headers: { 'User-Agent': USER_AGENT },
  });
  if (!pageRes.ok) return [];

  const html = await pageRes.text();
  const $ = cheerio.load(html);
  const chapters = [];

  $('audio.wp-audio-shortcode').each((i, audio) => {
    let streamUrl = $(audio).find('source').attr('src') ?? '';
    if (streamUrl.includes('?')) {
      streamUrl = streamUrl.substring(0, streamUrl.indexOf('?'));
    }
    if (streamUrl) {
      chapters.push({
        title: `Chapter ${i + 1}`,
        url: buildAudioProxyUrl(baseUrl, streamUrl, book.pageUrl),
        headers: null,
      });
    }
  });

  return chapters;
}

export async function getChapters(book, baseUrl) {
  switch (book.source) {
    case 'goldenaudiobook':
      return getGoldenChapters(book, baseUrl);
    case 'audiozaic':
      return getAudiozaicChapters(book, baseUrl);
    case 'appaudiobooks':
      return getAppAudiobooksChapters(book, baseUrl);
    default:
      return getTokyChapters(book, baseUrl);
  }
}
