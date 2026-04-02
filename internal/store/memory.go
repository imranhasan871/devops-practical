package store

import (
	"sync"

	"github.com/imranhasan871/devops-practical/internal/domain"
)

// MemoryStore is the in-memory implementation of ItemRepository.
// Concurrency-safe via a read/write mutex.
// Good enough for this demo; swap out for a real DB in production.
type MemoryStore struct {
	mu    sync.RWMutex
	items []domain.Item
}

// NewMemoryStore creates an initialised MemoryStore.
func NewMemoryStore() *MemoryStore {
	return &MemoryStore{
		items: make([]domain.Item, 0),
	}
}

// Save appends an item. O(1) amortised.
func (m *MemoryStore) Save(item domain.Item) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.items = append(m.items, item)
	return nil
}

// FindAll returns a snapshot of all items at the time of the call.
// We copy the slice so callers can't mess with internal state.
func (m *MemoryStore) FindAll() ([]domain.Item, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	result := make([]domain.Item, len(m.items))
	copy(result, m.items)
	return result, nil
}

// Count returns the current number of stored items.
func (m *MemoryStore) Count() int {
	m.mu.RLock()
	defer m.mu.RUnlock()
	return len(m.items)
}
