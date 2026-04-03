# ── Stage 1: Build ────────────────────────────────────────────────────────────
FROM golang:1.25-alpine AS builder

ARG APP_VERSION=v1

WORKDIR /app

# Install git (needed by some go modules)
RUN apk add --no-cache git

# Copy dependency files first to leverage Docker layer cache
COPY go.mod ./
RUN go mod download

# Copy source code
COPY . .

# Compile — strip debug info for smaller binary
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-w -s" -o service .

# ── Stage 2: Runtime ──────────────────────────────────────────────────────────
FROM alpine:3.18

ARG APP_VERSION=v1
ENV APP_VERSION=${APP_VERSION}

# Add CA certs and timezone data
RUN apk --no-cache add ca-certificates tzdata

WORKDIR /app

# Copy compiled binary
COPY --from=builder /app/service .

# Run as non-root user (K8s best practice)
RUN adduser -D -g '' appuser
USER appuser

EXPOSE 8080

HEALTHCHECK --interval=15s --timeout=3s --start-period=5s \
  CMD wget -qO- http://localhost:8080/health || exit 1

ENTRYPOINT ["./service"]
