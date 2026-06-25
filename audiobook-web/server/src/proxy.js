const USER_AGENT =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36';

export function getTokyProxyUrl(baseUrl, url, id, token, src) {
  return `${baseUrl}/toky-proxy?url=${encodeURIComponent(url)}&id=${encodeURIComponent(id)}&token=${encodeURIComponent(token)}&src=${encodeURIComponent(src)}`;
}

export async function handleTokyProxy(req, res, baseUrl) {
  const targetUrl = req.query.url;
  const audiobookId = req.query.id;
  const token = req.query.token;
  const trackSrc = req.query.src;

  if (!targetUrl) {
    return res.status(404).send('Missing url');
  }

  const baseUri = new URL(targetUrl);
  const decodedPath = decodeURIComponent(baseUri.pathname);
  const finalUrl = `https://tokybook.com${decodedPath}`;

  let finalTrackSrc = '';
  if (trackSrc) {
    finalTrackSrc = new URL(decodeURIComponent(trackSrc), 'https://tokybook.com').pathname;
  }

  const headers = {
    'User-Agent': USER_AGENT,
    Referer: 'https://tokybook.com/',
    Origin: 'https://tokybook.com',
    Accept: '*/*',
    ...(audiobookId ? { 'x-audiobook-id': audiobookId } : {}),
    ...(token ? { 'x-stream-token': token } : {}),
    'x-track-src': finalTrackSrc,
  };

  try {
    const proxyRes = await fetch(finalUrl, { headers });

    if (!proxyRes.ok) {
      return res.status(proxyRes.status).send(await proxyRes.text());
    }

    if (targetUrl.endsWith('.m3u8')) {
      const body = await proxyRes.text();
      const baseDir = targetUrl.substring(0, targetUrl.lastIndexOf('/') + 1);
      const baseSrcDir = trackSrc
        ? trackSrc.substring(0, trackSrc.lastIndexOf('/') + 1)
        : '';

      const rewrittenLines = body.split('\n').map((line) => {
        if (!line || line.startsWith('#')) return line;
        const segmentUrl = line.startsWith('http') ? line : `${baseDir}${line}`;
        const segmentSrc = line.startsWith('http') ? line : `${baseSrcDir}${line}`;
        return getTokyProxyUrl(
          baseUrl,
          segmentUrl,
          audiobookId ?? '',
          token ?? '',
          segmentSrc
        );
      });

      res.set('Content-Type', 'application/x-mpegURL');
      return res.send(rewrittenLines.join('\n'));
    }

    const buffer = Buffer.from(await proxyRes.arrayBuffer());
    res.set('Content-Type', proxyRes.headers.get('content-type') ?? 'video/mp2t');
    res.set('Access-Control-Allow-Origin', '*');
    return res.send(buffer);
  } catch (err) {
    console.error('[TokyProxy] Error:', err);
    return res.status(500).send(err.message);
  }
}

export async function handleAudioProxy(req, res) {
  const targetUrl = req.query.url;
  const referer = req.query.referer;

  if (!targetUrl) {
    return res.status(404).send('Missing url');
  }

  const headers = {
    'User-Agent': USER_AGENT,
    Accept: '*/*',
    ...(referer ? { Referer: referer } : {}),
  };

  try {
    const proxyRes = await fetch(targetUrl, { headers });

    if (!proxyRes.ok) {
      return res.status(proxyRes.status).send(await proxyRes.text());
    }

    const buffer = Buffer.from(await proxyRes.arrayBuffer());
    res.set('Content-Type', proxyRes.headers.get('content-type') ?? 'audio/mpeg');
    res.set('Access-Control-Allow-Origin', '*');
    res.set('Accept-Ranges', 'bytes');
    return res.send(buffer);
  } catch (err) {
    console.error('[AudioProxy] Error:', err);
    return res.status(500).send(err.message);
  }
}
