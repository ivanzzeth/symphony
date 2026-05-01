package workspace

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestCanonicalize_SimplePathWithinRoot(t *testing.T) {
	t.Parallel()

	root := t.TempDir()
	sub := filepath.Join(root, "subdir")
	require.NoError(t, os.MkdirAll(sub, 0o755))

	got, err := Canonicalize(root, "subdir")
	require.NoError(t, err)
	assert.Equal(t, sub, got)
}

func TestCanonicalize_AbsolutePathWithinRoot(t *testing.T) {
	t.Parallel()

	root := t.TempDir()
	sub := filepath.Join(root, "subdir")
	require.NoError(t, os.MkdirAll(sub, 0o755))

	got, err := Canonicalize(root, sub)
	require.NoError(t, err)
	assert.Equal(t, sub, got)
}

func TestCanonicalize_SymlinkWithinRoot(t *testing.T) {
	t.Parallel()

	root := t.TempDir()

	realDir := filepath.Join(root, "real")
	linkPath := filepath.Join(root, "link")
	require.NoError(t, os.MkdirAll(realDir, 0o755))
	require.NoError(t, os.Symlink(realDir, linkPath))

	got, err := Canonicalize(root, "link")
	require.NoError(t, err)
	assert.Equal(t, realDir, got)
}

func TestCanonicalize_SymlinkEscapesRoot(t *testing.T) {
	t.Parallel()

	root := t.TempDir()
	outside := t.TempDir()

	linkPath := filepath.Join(root, "escape")
	require.NoError(t, os.Symlink(outside, linkPath))

	_, err := Canonicalize(root, "escape")
	require.Error(t, err)
	assert.Contains(t, err.Error(), "escapes workspace root boundary")
}

func TestCanonicalize_SymlinkEscapesRootNested(t *testing.T) {
	t.Parallel()

	root := t.TempDir()
	outside := t.TempDir()

	sub := filepath.Join(root, "sub")
	require.NoError(t, os.MkdirAll(sub, 0o755))

	linkPath := filepath.Join(sub, "escape")
	require.NoError(t, os.Symlink(outside, linkPath))

	_, err := Canonicalize(root, "sub/escape")
	require.Error(t, err)
	assert.Contains(t, err.Error(), "escapes workspace root boundary")
}

func TestCanonicalize_NonExistentTrailingPreserved(t *testing.T) {
	t.Parallel()

	root := t.TempDir()
	existing := filepath.Join(root, "exists")
	require.NoError(t, os.MkdirAll(existing, 0o755))

	got, err := Canonicalize(root, "exists/nonexistent/file.txt")
	require.NoError(t, err)

	expected := filepath.Join(existing, "nonexistent", "file.txt")
	assert.Equal(t, expected, got)
}

func TestCanonicalize_SymlinkInPrefixNonExistentSuffix(t *testing.T) {
	t.Parallel()

	root := t.TempDir()

	realDir := filepath.Join(root, "real")
	linkPath := filepath.Join(root, "link")
	require.NoError(t, os.MkdirAll(realDir, 0o755))
	require.NoError(t, os.Symlink(realDir, linkPath))

	got, err := Canonicalize(root, "link/subdir/file.txt")
	require.NoError(t, err)

	expected := filepath.Join(realDir, "subdir", "file.txt")
	assert.Equal(t, expected, got)
}

func TestCanonicalize_RootEqualsResolved(t *testing.T) {
	t.Parallel()

	root := t.TempDir()

	got, err := Canonicalize(root, ".")
	require.NoError(t, err)
	assert.Equal(t, root, got)
}

func TestCanonicalize_RelativePathNotInRoot(t *testing.T) {
	t.Parallel()

	root := t.TempDir()
	outside := t.TempDir()

	_, err := Canonicalize(root, filepath.Join(outside, "other"))
	require.Error(t, err)
	assert.Contains(t, err.Error(), "escapes workspace root boundary")
}

func TestCanonicalize_SymlinkChainWithinRoot(t *testing.T) {
	t.Parallel()

	root := t.TempDir()

	realDir := filepath.Join(root, "real")
	link1 := filepath.Join(root, "link1")
	link2 := filepath.Join(root, "link2")
	require.NoError(t, os.MkdirAll(realDir, 0o755))
	require.NoError(t, os.Symlink(realDir, link1))
	require.NoError(t, os.Symlink(link1, link2))

	got, err := Canonicalize(root, "link2")
	require.NoError(t, err)
	assert.Equal(t, realDir, got)
}
