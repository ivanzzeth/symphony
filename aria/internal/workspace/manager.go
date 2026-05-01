package workspace

import (
	"context"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"sync"

	"github.com/charmbracelet/log"

	"github.com/ivanzzeth/symphony/aria/internal/types"
)

type Manager struct {
	baseDir    string
	baseBranch string
	gitBinary  string
	logger     *log.Logger

	hooks HooksHandler

	mu         sync.RWMutex
	active     map[string]string
	issueLocks sync.Map
}

// HooksHandler is an optional callback interface for workspace lifecycle hooks.
// Implementations are expected to be best-effort; errors are logged but do not
// block the primary operation.
type HooksHandler interface {
	RunAfterCreate(ctx context.Context, workspacePath string, issue types.Issue) error
	RunBeforeRemove(ctx context.Context, workspacePath string, issue types.Issue) error
}

// NopHooksHandler is a no-op hooks handler that always succeeds.
type NopHooksHandler struct{}

func (NopHooksHandler) RunAfterCreate(ctx context.Context, workspacePath string, issue types.Issue) error {
	return nil
}
func (NopHooksHandler) RunBeforeRemove(ctx context.Context, workspacePath string, issue types.Issue) error {
	return nil
}

// ManagerOption configures a Manager at construction time.
type ManagerOption func(*Manager)

// WithBaseBranch sets the base branch for new worktrees.
func WithBaseBranch(branch string) ManagerOption {
	return func(m *Manager) {
		if branch != "" {
			m.baseBranch = branch
		}
	}
}

// WithHooks sets the hooks handler for workspace lifecycle events.
func WithHooks(hooks HooksHandler) ManagerOption {
	return func(m *Manager) {
		if hooks != nil {
			m.hooks = hooks
		}
	}
}

// WithLogger sets the logger for the manager.
func WithLogger(logger *log.Logger) ManagerOption {
	return func(m *Manager) {
		if logger != nil {
			m.logger = logger
		}
	}
}

func NewManager(baseDir string, opts ...ManagerOption) *Manager {
	m := &Manager{
		baseDir:    baseDir,
		baseBranch: "develop",
		gitBinary:  "git",
		logger:     log.NewWithOptions(os.Stderr, log.Options{Level: log.WarnLevel}),
		hooks:      NopHooksHandler{},
		active:     make(map[string]string),
	}
	for _, opt := range opts {
		opt(m)
	}
	return m
}

func (m *Manager) Create(ctx context.Context, issue types.Issue) (string, error) {
	if issue.ID == "" {
		return "", errors.New("issue id is required")
	}

	unlock := m.lockIssue(issue.ID)
	defer unlock()

	workspacePath := m.workspacePath(issue.ID)

	workspacePath, err := Canonicalize(m.baseDir, workspacePath)
	if err != nil {
		return "", fmt.Errorf("create workspace: %w", err)
	}

	m.mu.RLock()
	trackedPath, tracked := m.active[issue.ID]
	m.mu.RUnlock()
	if tracked {
		if info, err := os.Stat(trackedPath); err == nil && info.IsDir() {
			return trackedPath, nil
		}
	}

	if info, err := os.Stat(workspacePath); err == nil && info.IsDir() {
		m.mu.Lock()
		m.active[issue.ID] = workspacePath
		m.mu.Unlock()
		return workspacePath, nil
	}

	if err := os.MkdirAll(filepath.Dir(workspacePath), 0o755); err != nil {
		return "", fmt.Errorf("create workspace parent directory: %w", err)
	}

	startRef := issue.ID
	if m.baseBranch != "" {
		if _, refErr := m.runGit(ctx, "rev-parse", "--verify", "origin/"+m.baseBranch); refErr == nil {
			startRef = "origin/" + m.baseBranch
		}
	}

	if _, err := m.runGit(ctx, "worktree", "add", workspacePath, "-b", issue.ID, startRef); err != nil {
		if _, fallbackErr := m.runGit(ctx, "worktree", "add", workspacePath, "-b", issue.ID); fallbackErr != nil {
			if _, fallback2Err := m.runGit(ctx, "worktree", "add", workspacePath, issue.ID); fallback2Err != nil {
				return "", fmt.Errorf("create git worktree for issue %s: primary add with -b failed: %v; fallback add failed: %w", issue.ID, err, fallback2Err)
			}
		}
	}

	m.mu.Lock()
	m.active[issue.ID] = workspacePath
	m.mu.Unlock()

	if err := m.hooks.RunAfterCreate(ctx, workspacePath, issue); err != nil {
		m.logger.Warn("after_create hook failed", "issue_id", issue.ID, "err", err)
	}

	return workspacePath, nil
}

func (m *Manager) Cleanup(ctx context.Context, issueID string) error {
	if issueID == "" {
		return nil
	}

	unlock := m.lockIssue(issueID)
	defer unlock()

	workspacePath := m.workspacePath(issueID)

	workspacePath, err := Canonicalize(m.baseDir, workspacePath)
	if err != nil {
		return fmt.Errorf("cleanup workspace: %w", err)
	}

	if _, err := os.Stat(workspacePath); errors.Is(err, os.ErrNotExist) {
		m.mu.Lock()
		delete(m.active, issueID)
		m.mu.Unlock()
		m.issueLocks.Delete(issueID)
		return nil
	}

	// Run before_remove hook before removing the worktree.
	// We pass an issue with just the ID since that's all we reliably have at cleanup time.
	if err := m.hooks.RunBeforeRemove(ctx, workspacePath, types.Issue{ID: issueID}); err != nil {
		m.logger.Warn("before_remove hook failed", "issue_id", issueID, "err", err)
	}

	output, err := m.runGit(ctx, "worktree", "remove", workspacePath, "--force")
	if err != nil {
		if !strings.Contains(output, "is not a working tree") {
			return fmt.Errorf("remove git worktree for issue %s: %w", issueID, err)
		}
	}

	m.mu.Lock()
	delete(m.active, issueID)
	m.mu.Unlock()
	m.issueLocks.Delete(issueID)

	return nil
}

// CleanupAll snapshots issue IDs tracked at the call start and cleans up only
// that snapshot. Any Create that starts after the snapshot may leave new active
// workspaces that require a later CleanupAll call.
func (m *Manager) CleanupAll(ctx context.Context) error {
	issueIDs := m.List()
	var errs []error

	for _, issueID := range issueIDs {
		if err := m.Cleanup(ctx, issueID); err != nil {
			errs = append(errs, err)
		}
	}

	if len(errs) > 0 {
		return errors.Join(errs...)
	}

	return nil
}

func (m *Manager) Exists(issueID string) bool {
	m.mu.RLock()
	workspacePath, ok := m.active[issueID]
	m.mu.RUnlock()
	if !ok {
		return false
	}

	info, err := os.Stat(workspacePath)
	return err == nil && info.IsDir()
}

func (m *Manager) List() []string {
	m.mu.RLock()
	issueIDs := make([]string, 0, len(m.active))
	for issueID := range m.active {
		issueIDs = append(issueIDs, issueID)
	}
	m.mu.RUnlock()

	sort.Strings(issueIDs)
	return issueIDs
}

func (m *Manager) workspacePath(issueID string) string {
	return filepath.Join(m.baseDir, "workspaces", issueID)
}

func (m *Manager) lockIssue(issueID string) func() {
	issueLock, _ := m.issueLocks.LoadOrStore(issueID, &sync.Mutex{})
	mu := issueLock.(*sync.Mutex)
	mu.Lock()
	return mu.Unlock
}

func (m *Manager) runGit(ctx context.Context, args ...string) (string, error) {
	cmd := exec.CommandContext(ctx, m.gitBinary, args...)
	cmd.Dir = m.baseDir
	output, err := cmd.CombinedOutput()
	if err == nil {
		return string(output), nil
	}

	var execErr *exec.Error
	if errors.As(err, &execErr) && errors.Is(execErr.Err, exec.ErrNotFound) {
		return string(output), fmt.Errorf("git executable not found: %w", err)
	}

	return string(output), fmt.Errorf("git %s failed: %w; output: %s", strings.Join(args, " "), err, strings.TrimSpace(string(output)))
}
