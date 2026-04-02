// Package store defines the repository interface (DIP).
// The service layer depends on this abstraction, not on any concrete
// implementation - making it trivial to swap memory for Redis or Postgres.
package store

import "github.com/imranhasan871/devops-practical/internal/domain"

// ItemRepository is the interface every storage backend must satisfy.
// Keeping it small (ISP) - only the methods the service actually needs.
type ItemRepository interface {
	Save(item domain.Item) error
	FindAll() ([]domain.Item, error)
	Count() int
}
