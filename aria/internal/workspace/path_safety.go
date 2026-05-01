package workspace

import (
	"errors"
	"fmt"
	"io/fs"
	"path/filepath"
	"strings"
)

// Canonicalize resolves all symlinks in path, anchored by root, and verifies
// the resolved canonical path stays within root's boundary.
//
// root is resolved to an absolute canonical path first. path is joined with
// root if relative, then all symlinks are resolved component by component.
// Non-existent trailing components are preserved after resolving the longest
// existing prefix.
func Canonicalize(root, path string) (string, error) {
	root, err := filepath.Abs(filepath.Clean(root))
	if err != nil {
		return "", fmt.Errorf("canonicalize root: %w", err)
	}
	root, err = filepath.EvalSymlinks(root)
	if err != nil {
		return "", fmt.Errorf("canonicalize root: %w", err)
	}

	clean := filepath.Clean(path)
	if !filepath.IsAbs(clean) {
		clean = filepath.Join(root, clean)
	}

	resolved, err := resolveExisting(clean)
	if err != nil {
		return "", fmt.Errorf("canonicalize: %w", err)
	}

	if resolved != root && !strings.HasPrefix(resolved, root+string(filepath.Separator)) {
		return "", fmt.Errorf("path escapes workspace root boundary: %s is outside %s", resolved, root)
	}

	return resolved, nil
}

// resolveExisting resolves symlinks in the longest existing prefix of path,
// then appends the remaining non-existent suffix.
func resolveExisting(path string) (string, error) {
	// Quick path: try resolving the whole path first.
	resolved, err := filepath.EvalSymlinks(path)
	if err == nil {
		return resolved, nil
	}
	if !errors.Is(err, fs.ErrNotExist) {
		return "", err
	}

	// Walk up the directory tree to find the longest existing prefix.
	candidate := filepath.Dir(path)
	for {
		resolved, err := filepath.EvalSymlinks(candidate)
		if err == nil {
			rel, relErr := filepath.Rel(candidate, path)
			if relErr != nil {
				return "", fmt.Errorf("relative path: %w", relErr)
			}
			return filepath.Join(resolved, rel), nil
		}
		if !errors.Is(err, fs.ErrNotExist) {
			return "", err
		}
		parent := filepath.Dir(candidate)
		if parent == candidate {
			// Reached filesystem root — nothing exists, return as-is.
			return path, nil
		}
		candidate = parent
	}
}
