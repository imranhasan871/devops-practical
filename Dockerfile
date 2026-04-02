# ---- build stage ----
FROM golang:1.22-alpine AS builder

# install git so go modules can fetch from VCS
RUN apk add --no-cache git ca-certificates tzdata

WORKDIR /app

# copy dependency files first - docker caches this layer if go.mod/go.sum
# haven't changed, which speeds up rebuilds a lot during active development
COPY go.mod go.sum ./
RUN go mod download

COPY . .

# build a static binary with all debug info stripped
# CGO_ENABLED=0 is required for the scratch/alpine final stage
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build \
    -ldflags="-w -s -X main.version=${APP_VERSION:-dev}" \
    -o /app/bin/server \
    ./cmd/server

# ---- final stage ----
# using alpine (not scratch) so we have a shell for exec probes
# and can run adduser without extra tools
FROM alpine:3.19

RUN apk add --no-cache ca-certificates tzdata && \
    addgroup -S appgroup && \
    adduser  -S appuser -G appgroup

WORKDIR /app

COPY --from=builder /app/bin/server ./server

# never run as root in production containers
USER appuser

EXPOSE 8080

# use exec form so signals (SIGTERM) reach our process directly,
# not a shell wrapper - required for graceful shutdown to work
ENTRYPOINT ["./server"]
