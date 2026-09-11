package migrations

import (
	"errors"

	"github.com/golang-migrate/migrate/v4"
	_ "github.com/golang-migrate/migrate/v4/database/postgres"
	_ "github.com/golang-migrate/migrate/v4/source/file"
)

func Up(sourceURL, databaseURL string) error {
	m, err := migrate.New(sourceURL, databaseURL)
	if err != nil {
		return err
	}
	defer closeMigration(m)
	if err := m.Up(); err != nil && !errors.Is(err, migrate.ErrNoChange) {
		return err
	}
	return nil
}

func Down(sourceURL, databaseURL string, steps int) error {
	m, err := migrate.New(sourceURL, databaseURL)
	if err != nil {
		return err
	}
	defer closeMigration(m)
	if err := m.Steps(-steps); err != nil && !errors.Is(err, migrate.ErrNoChange) && !errors.Is(err, migrate.ErrNilVersion) {
		return err
	}
	return nil
}

func Version(sourceURL, databaseURL string) (uint, bool, error) {
	m, err := migrate.New(sourceURL, databaseURL)
	if err != nil {
		return 0, false, err
	}
	defer closeMigration(m)
	version, dirty, err := m.Version()
	if errors.Is(err, migrate.ErrNilVersion) {
		return 0, false, nil
	}
	return version, dirty, err
}

func closeMigration(m *migrate.Migrate) {
	_, _ = m.Close()
}