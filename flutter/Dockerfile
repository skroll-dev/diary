FROM ghcr.io/cirruslabs/flutter:3.44.0 AS build

WORKDIR /app

COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

COPY . .
RUN flutter build web --release

FROM nginx:alpine

COPY --from=build /app/build/web /usr/share/nginx/html
COPY nginx.conf /etc/nginx/nginx.conf.template

ENV PORT=8080
EXPOSE 8080

# Cloud Run injects $PORT; envsubst replaces only ${PORT}, leaving nginx vars ($uri etc.) intact
CMD ["/bin/sh", "-c", "envsubst '${PORT}' < /etc/nginx/nginx.conf.template > /etc/nginx/conf.d/default.conf && nginx -g 'daemon off;'"]
