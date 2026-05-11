# Skill Writing Guide

Detailed writing guide for producing high-quality skills in the harness. Supplemental reference for SKILL.md Phase 4.

---

## Table of Contents

1. [Description Writing Patterns](#1-description-writing-patterns)
2. [Body Writing Style](#2-body-writing-style)
3. [Output Format Definition Patterns](#3-output-format-definition-patterns)
4. [Example Writing Patterns](#4-example-writing-patterns)
5. [Progressive Disclosure Patterns](#5-progressive-disclosure-patterns)
6. [Script Bundling Decision Criteria](#6-script-bundling-decision-criteria)
7. [Data Schema Standards](#7-data-schema-standards)
8. [What NOT to Include in Skills](#8-what-not-to-include-in-skills)

---

## 1. Description Writing Patterns

The description is the skill's sole trigger mechanism. Claude decides whether to use a skill based only on name + description from the `available_skills` list.

### Understanding the Trigger Mechanism

Claude tends not to invoke skills for simple tasks that can be easily handled with its built-in tools. Even with a perfect description, a simple request like "read this PDF" may not trigger. Complex, multi-step, specialized tasks have a higher trigger probability.

### Writing Principles

1. Describe both **what the skill does** + **concrete trigger situations**
2. Specify boundary conditions to distinguish similar-but-not-triggering cases
3. Be slightly "pushy" — compensate for Claude's conservative trigger tendency

### Good Examples

```yaml
description: "Perform all PDF operations: read PDF files, extract text/tables,
  merge, split, rotate, watermark, encrypt/decrypt, OCR. MUST use this skill
  whenever a .pdf file is mentioned or a PDF output is requested. Especially
  useful when transformation/editing/analysis is needed beyond simply
  'reading' a PDF."
```

```yaml
description: "All spreadsheet operations including Excel/CSV/TSV files: add
  columns, formula calculations, formatting, charts, data cleaning. Use this
  skill whenever the user mentions a spreadsheet file — even casually
  ('the xlsx in my Downloads folder')."
```

### Bad Examples

- `"Skill for processing data"` — too vague, unclear what files/operations
- `"PDF related tasks"` — no concrete actions listed, no trigger situations described

---

## 2. Body Writing Style

### Why-First Principle

LLMs that understand the reason make correct decisions in edge cases. Context delivery is more effective than dictatorial rules.

**Bad:**
```markdown
ALWAYS use pdfplumber for table extraction. NEVER use PyPDF2 for tables.
```

**Good:**
```markdown
Use pdfplumber for table extraction. PyPDF2 is specialized for text extraction
and cannot preserve table row/column structure. pdfplumber recognizes cell
boundaries and returns structured data.
```

### Generalization Principle

When issues are found in feedback or test results, generalize at the **principle level** rather than making narrow fixes for specific examples.

**Overfitting fix:**
```markdown
If there is a "Q4 Revenue" column, convert that column to numeric.
```

**Generalized fix:**
```markdown
If a column name contains keywords implying numeric values such as "revenue",
"amount", "quantity", convert that column to numeric type. Preserve the
original value if conversion fails.
```

### Imperative Tone

Use direct instructional language ("do X", "use Y"). A skill is a set of instructions.

### Context Economy

The context window is a shared resource. For every sentence, ask:
- "Does Claude already know this?" → delete
- "Would Claude make mistakes without this explanation?" → keep
- "Would one concrete example be more effective than a long explanation?" → replace with example

---

## 3. Output Format Definition Patterns

Use for skills where output format matters:

```markdown
## Report Structure
Follow this template exactly:

# [Title]
## Summary
## Key Findings
## Recommendations
```

Keep format definitions concise. Including real examples is more effective.

---

## 4. Example Writing Patterns

Examples are more effective than long explanations:

```markdown
## Commit Message Format

**Example 1:**
Input: Added JWT token-based user authentication
Output: feat(auth): implement JWT-based authentication

**Example 2:**
Input: Fixed bug where password visibility toggle button doesn't work on login page
Output: fix(login): fix password visibility toggle button behavior
```

---

## 5. Progressive Disclosure Patterns

### Pattern 1: Domain-Based Separation

```
bigquery-skill/
├── SKILL.md (overview + domain selection guide)
└── references/
    ├── finance.md (revenue, billing metrics)
    ├── sales.md (opportunities, pipeline)
    └── product.md (API usage, features)
```

When user asks about revenue, only finance.md is loaded.

### Pattern 2: Conditional Detail

```markdown
# DOCX Processing

## Document Creation
Create new documents with docx-js. → See [DOCX-JS.md](references/docx-js.md).

## Document Editing
For simple edits, modify XML directly.
**If track changes are needed**: See [REDLINING.md](references/redlining.md)
```

### Pattern 3: Large Reference File Structure

Reference files over 300 lines must include a Table of Contents at the top:

```markdown
# API Reference

## Table of Contents
1. [Authentication](#authentication)
2. [Endpoint List](#endpoint-list)
3. [Error Codes](#error-codes)
4. [Rate Limits](#rate-limits)

---

## Authentication
...
```

---

## 6. Script Bundling Decision Criteria

Observe agent transcripts during test runs. Bundle when these patterns appear:

| Signal | Action |
|--------|--------|
| Same helper script generated in 3 out of 3 tests | Bundle in `scripts/` |
| Same pip install / npm install repeated every run | Specify dependency installation step in skill |
| Same multi-step approach repeated | Document as standard procedure in skill body |
| Same error then same workaround repeated | Document known issue and resolution in skill |

Bundled scripts must pass execution testing.

---

## 7. Data Schema Standards

Use standard schemas for consistency in skill-to-skill data exchange. Usable for testing/evaluating harness-generated skills.

### eval_metadata.json

Metadata for each test case:

```json
{
  "eval_id": 0,
  "eval_name": "descriptive-name-here",
  "prompt": "The user's task prompt",
  "assertions": [
    "Output contains X",
    "File generated in Y format"
  ]
}
```

### grading.json

Assertion-based scoring results:

```json
{
  "expectations": [
    {
      "text": "Output includes 'Seoul'",
      "passed": true,
      "evidence": "Confirmed 'Seoul region data extraction' in step 3"
    }
  ],
  "summary": {
    "passed": 2,
    "failed": 1,
    "total": 3,
    "pass_rate": 0.67
  }
}
```

**Field name note:** Use `text`, `passed`, `evidence` exactly (no variants like `name`/`met`/`details`).

### timing.json

Execution time/token measurements:

```json
{
  "total_tokens": 84852,
  "duration_ms": 23332,
  "total_duration_seconds": 23.3
}
```

Save `total_tokens` and `duration_ms` immediately from sub-agent completion notifications. This data is only accessible at notification time and cannot be recovered later.

---

## 8. What NOT to Include in Skills

- Auxiliary docs: README.md, CHANGELOG.md, INSTALLATION_GUIDE.md
- Meta-information about the skill creation process (test results, iteration history)
- User-facing documentation (skills are instructions for AI agents)
- General knowledge Claude already possesses
