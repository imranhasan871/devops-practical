package middleware

import (
	"fmt"
	"net/http"
	"time"

	"github.com/google/uuid"
	appmetrics "github.com/imranhasan871/devops-practical/internal/metrics"
	"github.com/rs/zerolog/log"
)

// responseWriter wraps http.ResponseWriter so we can capture the status code
// after the handler writes it. Needed for logging and metrics.
type responseWriter struct {
	http.ResponseWriter
	statusCode int
	written    int64
}

func newResponseWriter(w http.ResponseWriter) *responseWriter {
	return &responseWriter{ResponseWriter: w, statusCode: http.StatusOK}
}

func (rw *responseWriter) WriteHeader(code int) {
	rw.statusCode = code
	rw.ResponseWriter.WriteHeader(code)
}

func (rw *responseWriter) Write(b []byte) (int, error) {
	n, err := rw.ResponseWriter.Write(b)
	rw.written += int64(n)
	return n, err
}

// RequestID injects a unique request ID into the response headers.
// Downstream services can use X-Request-ID to correlate logs.
func RequestID(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		reqID := r.Header.Get("X-Request-ID")
		if reqID == "" {
			reqID = uuid.New().String()
		}
		w.Header().Set("X-Request-ID", reqID)
		next.ServeHTTP(w, r)
	})
}

// Logger logs each incoming request with method, path, status, duration,
// and request ID. Structured JSON in production, pretty-printed in dev.
func Logger(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		rw := newResponseWriter(w)

		next.ServeHTTP(rw, r)

		duration := time.Since(start)

		log.Info().
			Str("method", r.Method).
			Str("path", r.URL.Path).
			Int("status", rw.statusCode).
			Dur("duration", duration).
			Str("remote_addr", r.RemoteAddr).
			Str("request_id", w.Header().Get("X-Request-ID")).
			Int64("bytes_written", rw.written).
			Msg("request")
	})
}

// Metrics updates Prometheus counters and histograms per request.
func Metrics(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		rw := newResponseWriter(w)

		appmetrics.HttpRequestsInFlight.Inc()
		defer appmetrics.HttpRequestsInFlight.Dec()

		next.ServeHTTP(rw, r)

		duration := time.Since(start).Seconds()
		statusStr := fmt.Sprintf("%d", rw.statusCode)

		appmetrics.HttpRequestsTotal.WithLabelValues(r.Method, r.URL.Path, statusStr).Inc()
		appmetrics.HttpRequestDuration.WithLabelValues(r.Method, r.URL.Path).Observe(duration)
	})
}

// Recoverer catches panics and returns a 500 instead of crashing the server.
// Logs the stack trace so we can actually figure out what went wrong.
func Recoverer(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			if rec := recover(); rec != nil {
				log.Error().
					Interface("panic", rec).
					Str("path", r.URL.Path).
					Msg("recovered from panic")
				http.Error(w, "Internal Server Error", http.StatusInternalServerError)
			}
		}()
		next.ServeHTTP(w, r)
	})
}
