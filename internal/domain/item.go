// Package domain holds the core business models.
// Nothing in here should depend on HTTP, databases, or any infrastructure.
// This is the innermost layer of the onion.
package domain

import (
	"errors"
	"time"
)

// Item is the central domain entity - a key/value pair submitted by clients.
type Item struct {
	ID        string      `json:"id"`
	Key       string      `json:"key"`
	Value     interface{} `json:"value"`
	CreatedAt time.Time   `json:"created_at"`
}

// CreateItemInput is the data required to create a new Item.
// Separating input from entity keeps the domain model clean.
type CreateItemInput struct {
	Key   string      `json:"key"`
	Value interface{} `json:"value"`
}

// Validate checks the input before we even attempt to persist anything.
func (c CreateItemInput) Validate() error {
	if c.Key == "" {
		return errors.New("field 'key' is required")
	}
	return nil
}
