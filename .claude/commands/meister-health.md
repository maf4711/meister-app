# /meister-health

**High-value health check for the Meister multi-platform Xcode project.**

When invoked, perform these minimal validation steps and report results clearly (use tables or bullet summary at end):

1. Confirm repo root (look for project.yml, MeisterIOS/, MeisterMacOS/).
2. Validate `project.yml` parses (run `xcodegen` if available; otherwise `head -30 project.yml`).
3. Check critical paths exist:
   - MeisterIOS/, MeisterMacOS/, MeisterTests/, MeisterMacOSTests/, MeisterWidget/, scripts/, docs/, fixtures/
   - Packages/MeisterKit (local SPM — may be gitignored)
   - Design system: ../meradOS/merados-design4 (from project.yml packages.MeradOSDesign4)
4. Run `git status --short`, `git log --oneline -3`, `git branch --show-current`.
5. Report key versions from project.yml: MARKETING_VERSION, CURRENT_PROJECT_VERSION, SWIFT_VERSION, deployment targets.
6. Check for remediation compliance markers: .claude/ exists with commands/, hooks/, status/current.md; .gitignore no longer blanket-ignores .claude/.
7. Optional quick: `xcodegen --spec project.yml --quiet` (do not persist .xcodeproj unless clean tree).
8. Summarize: "✅ Meister health: PASS" or list issues + recommended fixes. Mention recent design system migration (Design4) if relevant.

Keep output concise. Focus on actionable problems. This replaces manual "is the project in a good state?" checks.
