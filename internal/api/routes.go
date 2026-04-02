package api

import (
	"net/http"

	"github.com/go-chi/chi/v5"
	chimiddleware "github.com/go-chi/chi/v5/middleware"
	appmiddleware "github.com/imranhasan871/devops-practical/internal/middleware"
	"github.com/imranhasan871/devops-practical/internal/service"
	"github.com/imranhasan871/devops-practical/internal/store"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

// NewRouter wires up the full dependency graph and returns a ready-to-use
// http.Handler. All DI happens here so main.go stays trivially simple.
func NewRouter(version string) http.Handler {
	// build the dependency graph bottom-up
	repo := store.NewMemoryStore()
	itemSvc := service.NewItemService(repo)
	h := NewHandler(itemSvc, version)

	r := chi.NewRouter()

	// global middleware - applied to every request
	r.Use(chimiddleware.RealIP)    // trust X-Real-IP / X-Forwarded-For from nginx
	r.Use(appmiddleware.RequestID) // inject X-Request-ID before anything else
	r.Use(appmiddleware.Recoverer) // catch panics before they kill the server
	r.Use(appmiddleware.Metrics)   // prometheus counters + histograms
	r.Use(appmiddleware.Logger)    // structured request log per-request

	// infrastructure probes - fast, no business logic
	r.Get("/healthz", Healthz)
	r.Get("/readyz", Readyz)

	// prometheus scrape endpoint
	// in prod this should be restricted to internal traffic via nginx
	r.Handle("/metrics", promhttp.Handler())

	// application routes
	r.Get("/", h.GetIndex)
	r.Get("/status", h.GetStatus)
	r.Post("/data", h.PostData)
	r.Get("/data", h.GetData)

	return r
}
