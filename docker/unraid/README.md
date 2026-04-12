# Unraid — PlayTorrio Web

The web UI is a **static nginx** container (see `docker/web/Dockerfile`). There is no persistent data volume by default.

## Option A — Template from this repo (recommended)

1. **Copy the template** onto your Unraid flash drive:
   - Path on flash: `config/plugins/dockerMan/templates-user/playtorrio-web.xml`
   - Or download [playtorrio-web.xml](playtorrio-web.xml) from GitHub and place it there.

2. On Unraid: **Docker** → **Add Container** → open the **Template** dropdown → your user template **playtorrio-web** should appear (refresh page if needed).

3. **Build the image on Unraid** (once per update), via **Terminal** or SSH from a directory that contains the full repo:

   ```bash
   cd /path/to/PlayTorrioV2
   docker build -f docker/web/Dockerfile -t playtorrio-web:latest .
   ```

4. In the template form, leave **Repository** as `playtorrio-web:latest` (local image). Set **Web UI port** if you do not want **8089** on the host.

5. **Apply** → start the container → open `http://YOUR_UNRAID_IP:8089/`.

## Option B — Community Applications “template repository”

If you prefer a URL-based template list:

1. **Docker** → **Docker Hub** / template settings → add a **Template repository** URL pointing to the raw XML (only works if your CA/plugin supports custom repos; many users use Option A instead).

2. Build the image as in step 3 above.

## Docker Compose (any host, including Unraid)

From the **repository root**:

```bash
docker compose -f docker/web/docker-compose.yml up -d --build
```

Opens on **http://YOUR_IP:8089**. Edit `docker/web/docker-compose.yml` to change the host port.

## Option C — GitHub Container Registry (no build on Unraid)

If the [Docker Web (GHCR)](../../.github/workflows/docker-web.yml) workflow has run on `main`, pull the image:

```bash
docker pull ghcr.io/killamfkr/playtorrio-web:latest
```

In the Unraid template (or **Add Container**), set **Repository** to:

`ghcr.io/killamfkr/playtorrio-web:latest`

**Private repos / auth:** On Unraid **Docker** tab, add registry credentials for `ghcr.io` (GitHub PAT with `read:packages`). Public packages usually pull without login.

**Forks:** Use `ghcr.io/YOUR_GITHUB_USER/playtorrio-web:latest` after your fork’s workflow has pushed.

## Option D — Other registries

Build and push from any machine:

```bash
docker build -f docker/web/Dockerfile -t YOURUSER/playtorrio-web:latest .
docker push YOURUSER/playtorrio-web:latest
```

Edit **Repository** to `YOURUSER/playtorrio-web:latest`.

## Notes

- **Not** the full Android/desktop app: no magnet/torrent engine in the browser build.
- Change the host port in the template if **8089** conflicts (e.g. another app).
- For HTTPS, put **Nginx Proxy Manager**, **Traefik**, or **Swag** in front of this container; this template only exposes plain HTTP on the mapped port.
