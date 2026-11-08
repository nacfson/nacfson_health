FROM nginx:1.27-alpine

ARG SERVICE_VERSION=v0.0.0
ENV NGINX_ENTRYPOINT_QUIET_LOGS=1

# Static SPA shell (no bundler: index.html loads src/*.js as ES modules).
COPY nginx.conf /etc/nginx/nginx.conf
RUN sed -i "s|__SERVICE_VERSION__|${SERVICE_VERSION}|g" /etc/nginx/nginx.conf
COPY public /usr/share/nginx/html
COPY src /usr/share/nginx/html/src

EXPOSE 8080
# Built-in `nginx` user; the pod's securityContext overrides it with 10001.
USER 101:101
