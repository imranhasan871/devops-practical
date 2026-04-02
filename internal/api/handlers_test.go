package api

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/imranhasan871/devops-practical/internal/service"
	"github.com/imranhasan871/devops-practical/internal/store"
)

// newTestHandler sets up a Handler backed by a fresh MemoryStore.
// Using constructor injection makes testing straightforward - no mocking needed
// for the simple cases, just use the real in-memory store.
func newTestHandler() *Handler {
	repo := store.NewMemoryStore()
	svc := service.NewItemService(repo)
	return NewHandler(svc, "test")
}

func TestGetStatus_OK(t *testing.T) {
	h := newTestHandler()

	req := httptest.NewRequest(http.MethodGet, "/status", nil)
	rr := httptest.NewRecorder()

	h.GetStatus(rr, req)

	if rr.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rr.Code)
	}

	var resp StatusResponse
	if err := json.NewDecoder(rr.Body).Decode(&resp); err != nil {
		t.Fatalf("decode error: %v", err)
	}
	if resp.Status != "ok" {
		t.Errorf("expected status 'ok', got %q", resp.Status)
	}
	if resp.Version != "test" {
		t.Errorf("expected version 'test', got %q", resp.Version)
	}
}

func TestPostData_Valid(t *testing.T) {
	h := newTestHandler()

	body := `{"key":"region","value":"us-east-1"}`
	req := httptest.NewRequest(http.MethodPost, "/data", bytes.NewBufferString(body))
	req.Header.Set("Content-Type", "application/json")
	rr := httptest.NewRecorder()

	h.PostData(rr, req)

	if rr.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d: %s", rr.Code, rr.Body.String())
	}

	var item map[string]interface{}
	if err := json.NewDecoder(rr.Body).Decode(&item); err != nil {
		t.Fatalf("decode error: %v", err)
	}
	if item["key"] != "region" {
		t.Errorf("expected key 'region', got %v", item["key"])
	}
	if item["id"] == "" {
		t.Error("expected a non-empty ID")
	}
}

func TestPostData_MissingKey(t *testing.T) {
	h := newTestHandler()

	body := `{"value":"orphan"}`
	req := httptest.NewRequest(http.MethodPost, "/data", bytes.NewBufferString(body))
	req.Header.Set("Content-Type", "application/json")
	rr := httptest.NewRecorder()

	h.PostData(rr, req)

	if rr.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", rr.Code)
	}
}

func TestPostData_BadJSON(t *testing.T) {
	h := newTestHandler()

	req := httptest.NewRequest(http.MethodPost, "/data", bytes.NewBufferString("{bad"))
	req.Header.Set("Content-Type", "application/json")
	rr := httptest.NewRecorder()

	h.PostData(rr, req)

	if rr.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", rr.Code)
	}
}

func TestGetData_ReturnsList(t *testing.T) {
	h := newTestHandler()

	// seed one item first
	seedBody := `{"key":"k1","value":"v1"}`
	seedReq := httptest.NewRequest(http.MethodPost, "/data", bytes.NewBufferString(seedBody))
	seedReq.Header.Set("Content-Type", "application/json")
	h.PostData(httptest.NewRecorder(), seedReq)

	req := httptest.NewRequest(http.MethodGet, "/data", nil)
	rr := httptest.NewRecorder()
	h.GetData(rr, req)

	if rr.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rr.Code)
	}

	var resp map[string]interface{}
	_ = json.NewDecoder(rr.Body).Decode(&resp)

	if int(resp["count"].(float64)) != 1 {
		t.Errorf("expected count 1, got %v", resp["count"])
	}
}

func TestHealthz(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/healthz", nil)
	rr := httptest.NewRecorder()
	Healthz(rr, req)
	if rr.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rr.Code)
	}
}

func TestReadyz(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/readyz", nil)
	rr := httptest.NewRecorder()
	Readyz(rr, req)
	if rr.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rr.Code)
	}
}
