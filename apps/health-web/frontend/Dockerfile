FROM nginx:1.27-alpine

# Static SPA shell (no bundler: index.html loads src/*.js as ES modules).
COPY nginx.conf /etc/nginx/nginx.conf
COPY public /usr/share/nginx/html
COPY src /usr/share/nginx/html/src

EXPOSE 8080
# Built-in `nginx` user; the pod's securityContext overrides it with 10001.
USER 101:101
