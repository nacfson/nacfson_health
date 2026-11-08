# syntax=docker/dockerfile:1

# --- build -------------------------------------------------------------------
# Compile on the builder's native platform and cross-compile for the target,
# so multi-arch (amd64 + arm64) builds never run the Go toolchain under QEMU.
FROM --platform=$BUILDPLATFORM golang:1.23-bookworm AS build

WORKDIR /src
ARG TARGETOS TARGETARCH
ARG SERVICE_VERSION=v0.0.0
COPY go.mod go.sum ./
RUN go mod download
COPY . .

RUN CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH go build -trimpath -ldflags="-s -w -X main.version=${SERVICE_VERSION}" -o /out/api ./cmd/api \
    && CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH go build -trimpath -ldflags="-s -w -X main.version=${SERVICE_VERSION}" -o /out/migrate ./cmd/migrate

# --- runtime -----------------------------------------------------------------
# Migrations run through this same image (`./migrate up` then `./migrate seed`),
# so the SQL files and the master seed JSON ship with it.
FROM debian:bookworm-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates tzdata \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=build /out/api /out/migrate ./
COPY db ./db

ENV TZ=Asia/Seoul \
    APP_ADDR=:8080 \
    MIGRATIONS_PATH=file://db/migrations \
    SEED_PATH=db/master_exercise_seed_v12_6.json

EXPOSE 8080
USER 65532:65532
CMD ["./api"]
