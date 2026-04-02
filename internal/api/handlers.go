package api

import (
	"encoding/json"
	"net/http"
	"time"

	"github.com/imranhasan871/devops-practical/internal/domain"
	"github.com/imranhasan871/devops-practical/internal/service"
	"github.com/rs/zerolog/log"
)

// startTime is captured once so we can report uptime in /status
var startTime = time.Now()

// Handler holds all dependencies for the HTTP layer (DIP).
// Add new services here as the system grows - no global variables needed.
type Handler struct {
	itemSvc *service.ItemService
	version string
}

// NewHandler creates a Handler with its dependencies injected.
func NewHandler(itemSvc *service.ItemService, version string) *Handler {
	return &Handler{
		itemSvc: itemSvc,
		version: version,
	}
}

// StatusResponse is the shape of GET /status responses.
type StatusResponse struct {
	Status    string    `json:"status"`
	Version   string    `json:"version"`
	Uptime    string    `json:"uptime"`
	Timestamp time.Time `json:"timestamp"`
	ItemCount int       `json:"item_count"`
}

// ErrorResponse is returned on any error.
type ErrorResponse struct {
	Error   string `json:"error"`
	Code    int    `json:"code"`
}

// GetIndex handles GET / — returns a brief API index.
func (h *Handler) GetIndex(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]interface{}{
		"service":  "devops-practical",
		"version":  h.version,
		"endpoints": []string{
			"GET  /status",
			"GET  /data",
			"POST /data",
			"GET  /healthz",
			"GET  /readyz",
			"GET  /metrics",
		},
	})
}

// GetStatus handles GET /status
func (h *Handler) GetStatus(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, StatusResponse{
		Status:    "ok",
		Version:   h.version,
		Uptime:    time.Since(startTime).Round(time.Second).String(),
		Timestamp: time.Now().UTC(),
		ItemCount: h.itemSvc.Count(),
	})
}

// PostData handles POST /data
// Accepts {"key":"...","value":...} and persists a new Item.
func (h *Handler) PostData(w http.ResponseWriter, r *http.Request) {
	r.Body = http.MaxBytesReader(w, r.Body, 1<<20) // 1 MB cap

	var input domain.CreateItemInput
	if err := json.NewDecoder(r.Body).Decode(&input); err != nil {
		log.Warn().Err(err).Msg("invalid POST /data body")
		writeJSON(w, http.StatusBadRequest, ErrorResponse{
			Error: "invalid JSON body",
			Code:  http.StatusBadRequest,
		})
		return
	}

	item, err := h.itemSvc.Create(input)
	if err != nil {
		log.Warn().Err(err).Msg("failed to create item")
		writeJSON(w, http.StatusBadRequest, ErrorResponse{
			Error: err.Error(),
			Code:  http.StatusBadRequest,
		})
		return
	}

	writeJSON(w, http.StatusCreated, item)
}

// GetData handles GET /data - returns all stored items.
func (h *Handler) GetData(w http.ResponseWriter, r *http.Request) {
	items, err := h.itemSvc.List()
	if err != nil {
		log.Error().Err(err).Msg("failed to list items")
		writeJSON(w, http.StatusInternalServerError, ErrorResponse{
			Error: "failed to retrieve items",
			Code:  http.StatusInternalServerError,
		})
		return
	}

	writeJSON(w, http.StatusOK, map[string]interface{}{
		"count": len(items),
		"items": items,
	})
}

// Healthz is a minimal liveness probe for Kubernetes / load balancer.
func Healthz(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte(`{"status":"alive"}`))
}

// Readyz signals the app is ready to serve traffic.
// Extend this with real dependency checks (DB, cache) as needed.
func Readyz(w http.ResponseWriter, r *http.Request) {
	// TODO: ping DB, check cache connectivity, etc.
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte(`{"status":"ready"}`))
}

func writeJSON(w http.ResponseWriter, status int, v interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(v); err != nil {
		log.Error().Err(err).Msg("json encode error")
	}
}
