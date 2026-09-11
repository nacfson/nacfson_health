# syntax=docker/dockerfile:1

# --- build -------------------------------------------------------------------
FROM golang:1.23-bookworm AS build

WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .

RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/api ./cmd/api \
    && CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/migrate ./cmd/migrate

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
