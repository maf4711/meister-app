---
name: repo-remediation
description: >
  Perform a rigorous, systematic remediation of a codebase following the Elon Algorithm and strict development discipline.
  Use when the user wants to clean up a repository (git hygiene, architecture, compliance, testing, DX) using isolated worktrees, detailed planning, and parallel subagents.
  Trigger phrases: "remediate the repo", "do the full remediation program", "clean this up like we did with meister", "systematic repo cleanup", "repo remediation".
---

# Repo Remediation Skill

You are an expert at executing high-quality, low-risk codebase remediations using the team's proven methodology.

## Core Principles (non-negotiable)

1. **Elon Algorithm first**: Make Requirements Less Dumb → Delete → Simplify → Accelerate → Automate.
2. **Small, focused changes only**. Never mix concerns in one CL.
3. **Isolation is mandatory** for non-trivial work.
4. **Plan before you touch code**.
5. **Parallel execution for independent tracks** using subagents + worktrees.
6. **Verification before claiming done**.

## Mandatory Workflow

### Phase 0: Preparation
- Confirm you are in a git repository.
- Read the project's CLAUDE.md (if present) and any existing remediation docs.
- Ask the user for the high-level goal of the remediation if not obvious.

### Phase 1: Create a Detailed Plan
- Use the `writing-plans` skill (or equivalent structured planning).
- Break the work into clear **tracks** with priority:
  - **P0 (Critical)**: Things that make the repo uncloneable or unbuildable (gitignore, dependencies, Packages/, design system paths, etc.)
  - **P1 (Architecture)**: Big structural smells (giant switches, god classes, routing, etc.)
  - **P2 (Hygiene & Compliance)**: .claude/, docs, guards, scripts, repo policy
  - **P3 (Polish)**: Test naming, minor refactors, documentation
- Produce a plan document (save to `docs/superpowers/plans/` or similar when possible).
- Get explicit user approval on the track breakdown and order before proceeding.

### Phase 2: Isolation
- Use the `using-git-worktrees` skill for every non-trivial track.
- Create one dedicated worktree + branch per independent track.
- Never work on main for remediation work.

### Phase 3: Parallel Execution (when tracks are independent)
- Use `dispatching-parallel-agents` + `subagent-driven-development`.
- Dispatch one subagent per track in its isolated worktree.
- Each subagent must:
  - Follow TDD / RED-GREEN where applicable
  - Make small, frequent, high-quality commits
  - Report after every commit (`git log --oneline -3` + status)
  - Apply the Elon Algorithm internally
- The controller (you) monitors and only integrates clean, reviewed work.

### Phase 4: Integration
- Create one final integration branch from main.
- Merge tracks in priority order (P0 → P1 → P2 → P3), using `--no-ff` merges for clear history.
- Verify no conflicts and run relevant build/test commands.
- Clean up old worktrees and (optionally) old remediation branches after successful integration.

### Phase 5: Verification & Ship
- Run `xcodegen` / equivalent generators.
- Run builds and relevant tests.
- Bump version if this is release-worthy work.
- Push + clean up.

## Anti-Patterns to Avoid
- Doing remediation work directly on main
- Large "god" commits that touch everything
- Skipping the plan
- Running subagents without isolated worktrees
- Forgetting to clean up worktrees after integration
- Automating before the process is simplified

## Example Invocation
User: "Do the full meister-style remediation on this new repo."

You should:
1. Propose the track breakdown using the P0–P3 model.
2. Create a plan document.
3. Set up worktrees.
4. Dispatch parallel subagents for independent tracks.
5. Integrate, verify, and offer version bump + ship.

Always surface the plan and get buy-in before creating worktrees and dispatching agents.
