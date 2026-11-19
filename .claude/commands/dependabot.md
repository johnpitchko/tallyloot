# /dependabot

Resolve open Dependabot alerts and PRs for this repo.

## Steps

1. **Gather open work**
   - `gh api repos/tallyloot/app/dependabot/alerts --jq '.[] | select(.state=="open") | ...'` — security alerts with affected version ranges
   - `gh pr list --repo tallyloot/app --author app/dependabot` — open Dependabot PRs

2. **For each vulnerable gem, walk up the dependency graph first**
   - Identify which direct dependencies in `Gemfile` pull in the vulnerable gem (use `bundle exec gemfile-tree` or scan `Gemfile.lock`)
   - **Try updating the parent first:** `bundle update <direct-dep>` — if that brings the vulnerable gem to a safe version, prefer this path; the parent's maintainer has already vetted the combination
   - **Fall back to updating the gem directly:** `bundle update <vulnerable-gem>` if the parent hasn't caught up yet (still requires the vulnerable version)
   - **Only pin in `Gemfile`** as a last resort if neither `bundle update` path can reach a safe version due to conflicting constraints — and add a comment explaining why

3. **Flag major version bumps for separate handling**
   - Any gem jumping a major version (e.g. puma 6 → 8) must be in its own PR: check the changelog, run the full test suite, note breaking changes
   - Do not bundle major bumps with minor/patch fixes

4. **GitHub Actions updates** are YAML changes, not gem updates — handle in a separate PR by editing the relevant workflow files

5. **Verify** — run `bin/rails test` after all updates; do not commit if tests fail

6. **Commit and PR**
   - Group security fixes and routine minor/patch bumps into one PR per logical batch
   - Major version bumps get their own PR with changelog notes in the description
   - List which Dependabot PRs are superseded in the PR body

## Pinning guidance

The lockfile (`Gemfile.lock`) is the right place for exact versions — it is automatically updated by `bundle update`. Adding explicit version constraints to `Gemfile` for transitive deps is an anti-pattern: it creates noise and maintenance burden.

Only add a `Gemfile` constraint when:
- `bundle update` genuinely cannot reach a safe version without it due to conflicting constraints, **and**
- the gem is a transitive dep you don't otherwise control

If a direct dep needs a security floor (e.g. `gem 'openssl', '>= 3.3.1'`), add it with a comment explaining the reason.
