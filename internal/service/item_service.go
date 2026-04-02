// Package service contains business logic.
// It sits between the HTTP handlers and the data store, orchestrating
// domain rules and keeping both layers free of each other's concerns (SRP).
package service

import (
	"fmt"
	"time"

	"github.com/imranhasan871/devops-practical/internal/domain"
	appmetrics "github.com/imranhasan871/devops-practical/internal/metrics"
	"github.com/imranhasan871/devops-practical/internal/store"
)

// ItemService handles all operations related to Items.
type ItemService struct {
	repo store.ItemRepository
}

// NewItemService wires the service to its repository (DIP / constructor injection).
func NewItemService(repo store.ItemRepository) *ItemService {
	return &ItemService{repo: repo}
}

// Create validates the input, builds a domain entity, persists it,
// and updates observability metrics. Returns the saved item.
func (s *ItemService) Create(input domain.CreateItemInput) (domain.Item, error) {
	if err := input.Validate(); err != nil {
		return domain.Item{}, fmt.Errorf("validation failed: %w", err)
	}

	item := domain.Item{
		ID:        generateID(),
		Key:       input.Key,
		Value:     input.Value,
		CreatedAt: time.Now().UTC(),
	}

	if err := s.repo.Save(item); err != nil {
		return domain.Item{}, fmt.Errorf("failed to save item: %w", err)
	}

	appmetrics.DataItemsTotal.Inc()
	appmetrics.DataStoreSize.Set(float64(s.repo.Count()))

	return item, nil
}

// List returns all stored items.
func (s *ItemService) List() ([]domain.Item, error) {
	return s.repo.FindAll()
}

// Count returns the number of stored items.
func (s *ItemService) Count() int {
	return s.repo.Count()
}

func generateID() string {
	return fmt.Sprintf("%d", time.Now().UnixNano())
}
