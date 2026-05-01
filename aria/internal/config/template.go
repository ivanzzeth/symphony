package config

import (
	"fmt"
	"strings"

	"github.com/osteele/liquid"

	"github.com/ivanzzeth/symphony/aria/internal/types"
)

// TemplateContext holds all bindings available for liquid template rendering.
type TemplateContext struct {
	Issue     types.Issue
	Workspace TemplateWorkspace
	Tracker   TemplateTracker
	Attempt   int
}

// TemplateWorkspace holds workspace bindings for template expansion.
type TemplateWorkspace struct {
	BaseBranch string
	Path       string
}

// TemplateTracker holds tracker bindings for template expansion.
type TemplateTracker struct {
	Repo       string
	TeamID     string
	ProjectURL string
}

func RenderPrompt(cfg *WorkflowConfig, issue types.Issue, workspacePath string, attempt int) (string, error) {
	if cfg == nil {
		return "", fmt.Errorf("workflow config is nil")
	}
	return RenderTemplate(cfg.PromptTemplate, TemplateContext{
		Issue:   issue,
		Attempt: attempt,
		Workspace: TemplateWorkspace{
			BaseBranch: cfg.WorkspaceBaseBranch(),
			Path:       workspacePath,
		},
		Tracker: TemplateTracker{
			Repo:       cfg.GitHubRepo(),
			TeamID:     cfg.TrackerTeamID(),
			ProjectURL: cfg.TrackerProjectURL(),
		},
	})
}

// RenderHook expands liquid template variables in a hook command string.
// All string bindings are shell-quoted before interpolation to prevent command
// injection from user-controlled issue tracker values (titles, descriptions, etc.).
func RenderHook(hookTemplate string, ctx TemplateContext) (string, error) {
	engine := liquid.NewEngine()
	engine.StrictVariables()
	return engine.ParseAndRenderString(hookTemplate, shellQuotedBindings(ctx))
}

// shellQuotedBindings returns bindings with all string values shell-quoted
// for safe use in sh -c command strings.
func shellQuotedBindings(ctx TemplateContext) map[string]any {
	labels := ctx.Issue.Labels
	if labels == nil {
		labels = []string{}
	}

	issueState := ""
	if ctx.Issue.State != types.Unclaimed {
		issueState = ctx.Issue.State.String()
	}

	quotedLabels := make([]string, len(labels))
	for i, l := range labels {
		quotedLabels[i] = shellQuote(l)
	}

	return map[string]any{
		"issue": map[string]any{
			"id":          shellQuote(ctx.Issue.ID),
			"identifier":  shellQuote(ctx.Issue.Identifier),
			"title":       shellQuote(ctx.Issue.Title),
			"description": shellQuote(ctx.Issue.Description),
			"url":         shellQuote(ctx.Issue.URL),
			"state":       shellQuote(issueState),
			"labels":      quotedLabels,
			"priority":    ctx.Issue.Priority,
		},
		"workspace": map[string]any{
			"base_branch": shellQuote(ctx.Workspace.BaseBranch),
			"path":        shellQuote(ctx.Workspace.Path),
		},
		"tracker": map[string]any{
			"repo":        shellQuote(ctx.Tracker.Repo),
			"team_id":     shellQuote(ctx.Tracker.TeamID),
			"project_url": shellQuote(ctx.Tracker.ProjectURL),
		},
		"attempt": ctx.Attempt,
	}
}

// shellQuote wraps a string in single quotes and escapes embedded single quotes
// for safe use in sh -c command strings. Returns '' for empty strings.
func shellQuote(s string) string {
	if s == "" {
		return "''"
	}
	return "'" + strings.ReplaceAll(s, "'", "'\\''") + "'"
}

// buildBindings returns a map of all template bindings derived from the context.
// Callers can override or add keys before passing the result to the liquid engine.
func buildBindings(ctx TemplateContext) map[string]any {
	labels := ctx.Issue.Labels
	if labels == nil {
		labels = []string{}
	}

	issueState := ""
	if ctx.Issue.State != types.Unclaimed {
		issueState = ctx.Issue.State.String()
	}

	return map[string]any{
		"issue": map[string]any{
			"id":          ctx.Issue.ID,
			"identifier":  ctx.Issue.Identifier,
			"title":       ctx.Issue.Title,
			"description": ctx.Issue.Description,
			"url":         ctx.Issue.URL,
			"state":       issueState,
			"labels":      labels,
			"priority":    ctx.Issue.Priority,
		},
		"workspace": map[string]any{
			"base_branch": ctx.Workspace.BaseBranch,
			"path":        ctx.Workspace.Path,
		},
		"tracker": map[string]any{
			"repo":        ctx.Tracker.Repo,
			"team_id":     ctx.Tracker.TeamID,
			"project_url": ctx.Tracker.ProjectURL,
		},
		"attempt": ctx.Attempt,
	}
}

// RenderTemplate expands liquid template variables in a template string.
func RenderTemplate(template string, ctx TemplateContext) (string, error) {
	engine := liquid.NewEngine()
	engine.StrictVariables()
	return engine.ParseAndRenderString(template, buildBindings(ctx))
}

// RenderPath expands liquid template variables in a path string.
// It reuses buildBindings and overrides workspace.path with the base_dir alias.
func RenderPath(template string, ctx TemplateContext) (string, error) {
	engine := liquid.NewEngine()
	engine.StrictVariables()

	bindings := buildBindings(ctx)
	bindings["workspace"] = map[string]any{
		"base_branch": ctx.Workspace.BaseBranch,
		"base_dir":    ctx.Workspace.Path,
	}

	rendered, err := engine.ParseAndRenderString(template, bindings)
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(rendered), nil
}
