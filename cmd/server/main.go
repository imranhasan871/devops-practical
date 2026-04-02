package main

import (
	"context"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/imranhasan871/devops-practical/internal/api"
	"github.com/rs/zerolog"
	"github.com/rs/zerolog/log"
)

func main() {
	// pretty console output locally; structured JSON in production
	if os.Getenv("ENV") != "production" {
		log.Logger = log.Output(zerolog.ConsoleWriter{Out: os.Stderr, TimeFormat: time.RFC3339})
	}

	port := getEnv("PORT", "8080")
	version := getEnv("APP_VERSION", "dev")

	router := api.NewRouter(version)

	srv := &http.Server{
		Addr:    ":" + port,
		Handler: router,

		// explicit timeouts - without these, slow clients can tie up goroutines
		// indefinitely and eventually exhaust the pool under load
		ReadTimeout:       15 * time.Second,
		ReadHeaderTimeout: 5 * time.Second,
		WriteTimeout:      15 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	go func() {
		log.Info().
			Str("port", port).
			Str("version", version).
			Str("env", getEnv("ENV", "development")).
			Msg("server starting")

		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatal().Err(err).Msg("server error")
		}
	}()

	// block until we receive SIGINT or SIGTERM
	// docker stop and kubectl rollout both send SIGTERM
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	sig := <-quit

	log.Info().Str("signal", sig.String()).Msg("starting graceful shutdown")

	// give in-flight requests 30 seconds to complete
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	if err := srv.Shutdown(ctx); err != nil {
		log.Fatal().Err(err).Msg("graceful shutdown failed")
	}

	log.Info().Msg("server stopped cleanly")
}

func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
