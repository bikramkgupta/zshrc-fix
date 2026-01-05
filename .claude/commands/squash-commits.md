# Smart Commit Squash

Analyze and intelligently squash commits in a GitHub repository into high-level logical groups.

## Input
Repository: $ARGUMENTS (format: owner/repo or full GitHub URL)

## Workflow

### Phase 1: Fetch and Analyze Commits

1. Clone or fetch the repository if needed:
   ```bash
   gh repo clone $ARGUMENTS --depth=100 2>/dev/null || cd $(basename $ARGUMENTS .git)
   ```

2. Get the commit history with details:
   ```bash
   git log --oneline --no-merges -50
   git log --format="%H|%s|%an|%ad|%b" --no-merges -50
   ```

3. Analyze commit patterns looking for:
   - Conventional commit prefixes (feat:, fix:, refactor:, docs:, chore:, test:)
   - Related file changes (use `git show --stat <hash>`)
   - Temporal clustering (commits within short timeframes)
   - Author grouping
   - Semantic similarity in commit messages

### Phase 2: Propose Squash Groups

Present a structured proposal with this format:

```
## Proposed Squash Plan

### Group 1: [High-level description]
Commits to squash: abc1234, def5678, ghi9012
Files affected: src/auth/*, tests/auth/*
Proposed message: "feat(auth): implement OAuth2 login flow with Google provider"
Reasoning: [Why these belong together]

### Group 2: [High-level description]
...

### Commits to keep separate:
- xyz7890: "fix(critical): resolve production memory leak" - Breaking change, keep isolated

## Summary
- Total commits: X
- After squash: Y commits
- Reduction: Z%
```

### Phase 3: User Alignment

Ask: "Does this squash plan look good? You can:
- Approve all (type 'yes' or 'approve')
- Modify groups (e.g., 'merge group 1 and 2', 'split group 3')
- Exclude commits (e.g., 'keep abc1234 separate')
- Abort (type 'no' or 'abort')"

### Phase 4: Execute Squash

Upon approval, execute using interactive rebase:

```bash
# Create a backup branch first
git checkout -b backup-before-squash-$(date +%Y%m%d-%H%M%S)
git checkout -

# For each group, perform squash
git rebase -i <base-commit>
# Programmatically edit the rebase-todo file or guide user through interactive process
```

For remote execution (force push warning):
```bash
# Show what will change
git log --oneline origin/main..HEAD

# Confirm before force push
echo "This will rewrite history on remote. Proceed? (yes/no)"
```

If confirmed:
```bash
gh pr create --title "Squashed commits" --body "..." 2>/dev/null || git push --force-with-lease
```

## Safety Rules

1. NEVER force push to main/master without explicit confirmation
2. ALWAYS create backup branch before rebase
3. WARN if commits are already pushed to remote
4. CHECK for open PRs that might be affected
5. PRESERVE merge commits unless explicitly told to flatten

## Grouping Heuristics

Prioritize grouping by:
1. **Feature scope**: feat: commits touching same module
2. **Bug fixes**: Related fix: commits for same issue
3. **Refactoring**: refactor: commits in same area
4. **WIP cleanup**: Commits with "wip", "temp", "fixup", "squash" in message
5. **Time window**: Multiple commits by same author within 2 hours
