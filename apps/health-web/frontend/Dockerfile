FROM nginx:1.27-alpine

# Static SPA shell (no bundler: index.html loads src/*.js as ES modules).
COPY nginx.conf /etc/nginx/nginx.conf
COPY public /usr/share/nginx/html
COPY src /usr/share/nginx/html/src

EXPOSE 80
