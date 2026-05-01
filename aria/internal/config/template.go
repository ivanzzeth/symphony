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
func RenderHook(hookTemplate string, ctx TemplateContext) (string, error) {
	return RenderTemplate(hookTemplate, ctx)
}

// RenderTemplate expands liquid template variables in a template string.
func RenderTemplate(template string, ctx TemplateContext) (string, error) {
	engine := liquid.NewEngine()
	engine.StrictVariables()

	labels := ctx.Issue.Labels
	if labels == nil {
		labels = []string{}
	}

	issueState := ""
	if ctx.Issue.State != types.Unclaimed {
		issueState = ctx.Issue.State.String()
	}

	bindings := map[string]any{
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

	return engine.ParseAndRenderString(template, bindings)
}

// RenderPath expands liquid template variables in a path string.
func RenderPath(template string, ctx TemplateContext) (string, error) {
	engine := liquid.NewEngine()
	engine.StrictVariables()

	labels := ctx.Issue.Labels
	if labels == nil {
		labels = []string{}
	}

	bindings := map[string]any{
		"issue": map[string]any{
			"id":          ctx.Issue.ID,
			"identifier":  ctx.Issue.Identifier,
			"title":       ctx.Issue.Title,
			"description": ctx.Issue.Description,
			"url":         ctx.Issue.URL,
			"labels":      labels,
		},
		"workspace": map[string]any{
			"base_branch": ctx.Workspace.BaseBranch,
			"base_dir":    ctx.Workspace.Path,
		},
		"tracker": map[string]any{
			"repo":        ctx.Tracker.Repo,
			"team_id":     ctx.Tracker.TeamID,
			"project_url": ctx.Tracker.ProjectURL,
		},
	}

	rendered, err := engine.ParseAndRenderString(template, bindings)
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(rendered), nil
}
