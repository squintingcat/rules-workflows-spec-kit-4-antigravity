---
trigger: always_on
---

# Git Workflow Rules

You are working in a Git-controlled project. Follow these rules regarding version control:

## Commits
1. **DO NOT Auto-Commit**: Never run `git commit` immediately after modifying files unless explicitly asked by the user.
2. **User Review First**: Always allow the user to review file changes (edits) first.
3. **Explicit Confirmation**: Only run `git commit` when the user signals that the changes are accepted or asks you to `save` or `checkpoint` the work.

## Index and Staging Safety
1. **Do Not Touch Staging by Default**: Never run commands that modify the Git index or staging area.
2. **Forbidden Without Explicit User Instruction**:
   - `git add`
   - `git restore --staged`
   - `git reset` (any mode)
   - `git rm --cached`
   - `git mv`
   - `git commit`
   - `git stash`
   - `git checkout -- <path>`
3. **Read-Only Git Commands Only**: For inspection use read-only commands such as `git status`, `git diff`, `git diff --cached`, `git log`, `git show`.
4. **VS Code Source Control Ownership**: Assume the user manages staging/unstaging/commit in the VS Code Source Control UI unless explicitly requested otherwise.
