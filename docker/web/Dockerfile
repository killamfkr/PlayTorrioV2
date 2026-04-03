# Build Flutter web, then serve static files with nginx.
# Usage (from repo root):
#   docker build -f docker/web/Dockerfile -t playtorrio-web .
#   docker run --rm -p 8089:80 playtorrio-web

FROM ghcr.io/cirruslabs/flutter:stable AS build
WORKDIR /app
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get
COPY . .
RUN flutter build web --release

FROM nginx:alpine
COPY docker/web/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/build/web /usr/share/nginx/html
EXPOSE 80
