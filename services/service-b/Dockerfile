# ── Stage 1: Build ────────────────────────────────────────────────────────────
FROM golang:1.25-alpine AS builder

ARG APP_VERSION=v1

WORKDIR /app

RUN apk add --no-cache git

COPY go.mod ./
COPY go.sum* ./
RUN go mod download

COPY . .

RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-w -s" -o service .

# ── Stage 2: Runtime ──────────────────────────────────────────────────────────
FROM alpine:3.18

ARG APP_VERSION=v1
ENV APP_VERSION=${APP_VERSION}

RUN apk --no-cache add ca-certificates tzdata

WORKDIR /app

COPY --from=builder /app/service .

RUN adduser -D -g '' appuser
USER appuser

EXPOSE 8080

HEALTHCHECK --interval=15s --timeout=3s --start-period=5s \
  CMD wget -qO- http://localhost:8080/health || exit 1

ENTRYPOINT ["./service"]
