package config

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/ivanzzeth/symphony/aria/internal/types"
)

func TestRenderTemplate(t *testing.T) {
	t.Parallel()

	issue := types.Issue{
		ID:          "ISS-101",
		Identifier:  "SYM-101",
		Title:       "Implement workflow parser",
		Description: "Add parser, defaults, and tests for WORKFLOW.md",
		URL:         "https://linear.app/example/issue/SYM-101",
		State:       types.Unclaimed,
		Priority:    2,
		Labels:      []string{"feature", "go"},
	}

	ctx := TemplateContext{
		Issue: issue,
		Workspace: TemplateWorkspace{
			BaseBranch: "develop",
			Path:       "/tmp/workspaces/ISS-101",
		},
		Tracker: TemplateTracker{
			Repo:       "symphony",
			TeamID:     "WEB",
			ProjectURL: "https://linear.app/example/project/symphony",
		},
		Attempt: 1,
	}

	tests := []struct {
		name     string
		template string
		want     string
		wantErr  bool
	}{
		{
			name:     "renders issue fields",
			template: "Title: {{ issue.title }}\nDescription: {{ issue.description }}\nURL: {{ issue.url }}",
			want:     "Title: Implement workflow parser\nDescription: Add parser, defaults, and tests for WORKFLOW.md\nURL: https://linear.app/example/issue/SYM-101",
			wantErr:  false,
		},
		{
			name:     "renders issue id and identifier",
			template: "Issue: {{ issue.id }} ({{ issue.identifier }})",
			want:     "Issue: ISS-101 (SYM-101)",
			wantErr:  false,
		},
		{
			name:     "renders issue labels",
			template: "Labels: {{ issue.labels | join: \", \" }}",
			want:     "Labels: feature, go",
			wantErr:  false,
		},
		{
			name:     "renders issue priority",
			template: "Priority: {{ issue.priority }}",
			want:     "Priority: 2",
			wantErr:  false,
		},
		{
			name:     "renders workspace bindings",
			template: "Branch: {{ workspace.base_branch }}\nPath: {{ workspace.path }}",
			want:     "Branch: develop\nPath: /tmp/workspaces/ISS-101",
			wantErr:  false,
		},
		{
			name:     "renders tracker bindings",
			template: "Repo: {{ tracker.repo }}\nTeam: {{ tracker.team_id }}\nURL: {{ tracker.project_url }}",
			want:     "Repo: symphony\nTeam: WEB\nURL: https://linear.app/example/project/symphony",
			wantErr:  false,
		},
		{
			name:     "renders attempt",
			template: "Attempt #{{ attempt }}",
			want:     "Attempt #1",
			wantErr:  false,
		},
		{
			name:     "renders combined bindings",
			template: "{{ issue.identifier }} in {{ workspace.path }} (attempt {{ attempt }})",
			want:     "SYM-101 in /tmp/workspaces/ISS-101 (attempt 1)",
			wantErr:  false,
		},
		{
			name:     "fails on unknown variable",
			template: "{{ issue.missing_field }}",
			wantErr:  true,
		},
		{
			name:     "fails on unknown filter",
			template: "{{ issue.title | no_such_filter }}",
			wantErr:  true,
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			out, err := RenderTemplate(tt.template, ctx)
			if tt.wantErr {
				require.Error(t, err)
				return
			}

			require.NoError(t, err)
			assert.Equal(t, tt.want, out)
		})
	}
}

func TestRenderPrompt(t *testing.T) {
	t.Parallel()

	cfg := &WorkflowConfig{
		PromptTemplate: "Fix {{ issue.identifier }}: {{ issue.title }}",
		Workspace: WorkspaceConfig{
			BaseBranch: "main",
		},
		Tracker: TrackerConfig{
			Repo: "myrepo",
		},
	}

	issue := types.Issue{
		ID:          "ISS-1",
		Identifier:  "PROJ-42",
		Title:       "Test feature",
		Description: "desc",
		URL:         "https://example.com/PROJ-42",
	}

	out, err := RenderPrompt(cfg, issue, "/ws/ISS-1", 0)
	require.NoError(t, err)
	assert.Equal(t, "Fix PROJ-42: Test feature", out)
}

func TestRenderPrompt_NilConfig(t *testing.T) {
	t.Parallel()

	_, err := RenderPrompt(nil, types.Issue{}, "", 0)
	require.Error(t, err)
	assert.Contains(t, err.Error(), "workflow config is nil")
}

func TestRenderPath(t *testing.T) {
	t.Parallel()

	ctx := TemplateContext{
		Issue: types.Issue{
			ID:         "WEB-39",
			Identifier: "WEB-39",
		},
		Workspace: TemplateWorkspace{
			BaseBranch: "develop",
		},
	}

	tests := []struct {
		name     string
		template string
		want     string
	}{
		{
			name:     "expands issue id in path",
			template: "workspaces/{{ issue.id }}",
			want:     "workspaces/WEB-39",
		},
		{
			name:     "plain path unchanged",
			template: ".",
			want:     ".",
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			out, err := RenderPath(tt.template, ctx)
			require.NoError(t, err)
			assert.Equal(t, tt.want, out)
		})
	}
}

func TestRenderHook(t *testing.T) {
	t.Parallel()

	ctx := TemplateContext{
		Issue: types.Issue{
			ID:         "WEB-39",
			Identifier: "WEB-39",
		},
		Workspace: TemplateWorkspace{
			BaseBranch: "develop",
			Path:       "/tmp/ws/WEB-39",
		},
		Tracker: TemplateTracker{
			Repo:       "symphony",
			ProjectURL: "https://linear.app/example/project/symphony",
		},
	}

	tests := []struct {
		name     string
		template string
		want     string
	}{
		{
			name:     "hook with base branch (shell-quoted)",
			template: "git clone --branch {{ workspace.base_branch }} https://github.com/example/repo .",
			want:     "git clone --branch 'develop' https://github.com/example/repo .",
		},
		{
			name:     "hook with workspace path (shell-quoted)",
			template: "cd {{ workspace.path }} && make build",
			want:     "cd '/tmp/ws/WEB-39' && make build",
		},
		{
			name:     "hook with shell-quoted empty title",
			template: "git commit -m {{ issue.title }}",
			want:     "git commit -m ''",
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			out, err := RenderHook(tt.template, ctx)
			require.NoError(t, err)
			assert.Equal(t, tt.want, out)
		})
	}
}
