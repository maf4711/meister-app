# CLAUDE.md — Project Conventions & Workflow

This file defines the required standards for working on this project.

## Core Principles (Elon Algorithm)

1. **Make Requirements Less Dumb** — Question every requirement. If you haven't rejected it at least once, you don't take it seriously enough.
2. **Delete** — Remove anything not absolutely necessary. If you don't end up putting ~10% back, you didn't delete enough.
3. **Simplify & Optimize** — Only after deletion.
4. **Accelerate** — Only after simplification.
5. **Automate** — Only after acceleration. Never automate a broken process.

## Mandatory Workflow

**Every code change** (feature, bugfix, refactor, config) **MUST** follow the `development-workflow` skill:
- Requirements first (check `requirements` table if applicable)
- Worktree isolation for non-trivial changes
- Test strategy before implementation
- All tests must fail before writing code (RED phase)
- Implement → simplify → commit loop
- Final simplifier pass before PR

## Key Conventions

- MeisterKit is the single source of truth for native code shared between platforms.
- Use the installed `repo-maintenance` skill for structure validation when working on skills/agents.
- Every significant project should have a `.claude/` directory for custom commands, hooks, and status.
- Prefer native tools and minimal dependencies.
- Track costs where LLM usage is involved.
- Follow the meradOS style: clean, principled, no unnecessary abstraction.

## Development Practices

- Small, focused changes.
- Description explains **why**, not just what.
- Push back on complexity with data or first principles.
- Clean up after yourself (no leftover branches, worktrees, or dead code).

## When in Doubt

- Delete first.
- Check existing CLAUDE.md files in sibling projects for patterns.
- Run the multi-repo health report or repo-maintenance tools.
