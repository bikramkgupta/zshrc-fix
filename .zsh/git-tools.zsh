# git-tools.zsh - Git & Worktree power-user aliases
# Run 'ghelp' for available commands
# UX: worktree repo layout uses .bare/ at repo root

setopt NO_NOMATCH 2>/dev/null

# ============================================================================
# HELPERS
# ============================================================================

_git_tools_err() { print -r -- "git-tools: $*" >&2; }
_git_tools_ok()  { print -r -- "$*"; }

_git_tools_show_help() {
  case "$1" in -h|--help) printf '%s\n' "$2"; return 0 ;; esac
  return 1
}

_git_tools_confirm() {
  local prompt="${1:-Continue?}"
  local reply
  read -r "reply?$prompt [y/N] "
  [[ "$reply" == "y" || "$reply" == "Y" ]]
}

_git_tools_in_git() { git rev-parse --is-inside-work-tree >/dev/null 2>&1; }

_git_tools_find_root() {
  local d="$PWD"
  while [[ "$d" != "/" ]]; do
    if [[ -d "$d/.bare" ]]; then
      (cd "$d" && pwd -P)
      return 0
    fi
    d="${d:h}"
  done
  return 1
}

_git_tools_root() {
  local root
  root="$(_git_tools_find_root)" && { print -r -- "$root"; return 0; }

  if _git_tools_in_git; then
    local common
    common="$(git rev-parse --git-common-dir 2>/dev/null)" || return 1
    common="$(cd "$(dirname "$common")" 2>/dev/null && pwd -P)/$(basename "$common")"
    if [[ -d "$common" && -d "$(dirname "$common")/.bare" ]]; then
      print -r -- "$(cd "$(dirname "$common")" && pwd -P)"
      return 0
    fi
  fi

  _git_tools_err "could not find repo root with .bare/"
  return 1
}

_git_tools_dir_for_branch() {
  local b="$1"
  local root="$2"
  local safe_b="${b//\\//__}"
  if [[ -n "$root" ]]; then
    print -r -- "${root:t}-${safe_b}"
  else
    print -r -- "$safe_b"
  fi
}

_git_tools_default_base() {
  if git show-ref --verify --quiet refs/remotes/origin/main; then print -r -- "origin/main"; return; fi
  if git show-ref --verify --quiet refs/remotes/origin/master; then print -r -- "origin/master"; return; fi
  if git show-ref --verify --quiet refs/heads/main; then print -r -- "main"; return; fi
  if git show-ref --verify --quiet refs/heads/master; then print -r -- "master"; return; fi
  print -r -- "HEAD"
}

_git_tools_dir_empty() {
  local d="$1"
  [[ -d "$d" ]] || return 0
  [[ -z "$(command ls -A "$d" 2>/dev/null)" ]]
}

_git_tools_parse_flags() {
  __GT_YES=0
  __GT_SAFE=1
  __GT_ARGS=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --yes|-y) __GT_YES=1; shift ;;
      --safe)   __GT_SAFE=1; shift ;;
      --unsafe) __GT_SAFE=0; shift ;;
      --) shift; __GT_ARGS+=("$@"); break ;;
      *)  __GT_ARGS+=("$1"); shift ;;
    esac
  done
}

# ============================================================================
# HELP SYSTEM
# ============================================================================

ghelp() {
  cat <<'EOF'
Git Tools - Power User Commands
================================

REPO INITIALIZATION & SHIPPING:
  gwt-ship <name> <br>   Init repo + GitHub remote + push (all-in-one)
  gwt-init-empty <dir>   Init new local bare repo structure
  gwt-clone-bare <url>   Clone existing repo into bare structure
  gwt-init-bare <url>    Same as clone-bare (legacy)

WORKTREE OPERATIONS:
  gwt-new <br> [base]    Create new branch + worktree
  gwt-newpush <br> ...   Create new branch + worktree + push
  gwt-add <br>           Create worktree for existing branch
  gwt-go <br>            Switch to worktree directory
  gwt-rm <path>          Remove worktree
  gwt-ls                 List worktrees
  gwt-prune              Prune stale worktrees
  gwt-sync               Fetch all + show status of all worktrees
  gwt-rebase-all         Rebase all worktrees on main & push
  gwt-status-all         Show status summary for all worktrees
  gwt-lock/unlock <wt>   Lock/unlock worktree
  gwt-repair             Repair worktree links
  gwf / gwt-fzf          Fuzzy find worktree and switch

BRANCH MANAGEMENT:
  gbr-ls                 List branches (verbose)
  gbr-merged             List merged branches
  gbr-unmerged           List unmerged branches
  gbr-remote             List remote branches
  gbr-newpush <br>       Create branch and push immediately
  gbr-track <br> [rem]   Track remote branch
  gbr-nuke <br>          Delete branch everywhere (local+remote+worktree)

CORE GIT ALIASES:
  g, gs, gss             git status (short/full)
  gl, gll, glo           git log (graph/full/oneline)
  ga, gaa, gap           git add (., all, patch)
  gc, gcm                git commit (msg)
  gca, gcan              git commit amend (no-edit)
  gco, gsw, gswc         Checkout / switch / create switch
  gf, gp, gP, gPu        Fetch, Pull (rebase), Push, Push upstream
  gPf                    Force push (lease)
  gdf, gds, gdn          Diff (unstaged, staged, name-only)
  grh, grs, gundo        Reset (hard, soft, undo last commit)
  gcp, gcpc, gcpa        Cherry-pick (continue, abort)
  gsh, gshf              Show commit (stat, full)
  grl, grlp              Reflog (pretty, short)
  gt, gtl, gta           Tags (list, sort, annotate)
  gclean, gclean-dry     Clean untracked files

REBASE & STASH:
  grb, grbm              Rebase (on base / on main)
  grbi, grbia            Interactive rebase (autosquash)
  grbc, grba, grbs       Rebase continue / abort / skip
  gst, gstp              Stash / pop
  gst-ls, gst-show       List / show stash
  gst-drop, gst-save     Drop / save stash

REMOTES:
  gremote-ls             List remotes
  gremote-add <nm> <url> Add remote
  gremote-gh <nm> <repo> Add remote from GitHub (owner/repo)

Run 'ghelp' anytime to show this help.
EOF
}

# ============================================================================
# CORE GIT ALIASES
# ============================================================================

alias g='git'
alias gs='git status -sb'
alias gss='git status'
alias gl='git log --oneline --decorate --graph -n 30'
alias gll='git log --decorate --graph'
alias glo='git log --oneline -n 20'
alias ga='git add'
alias gaa='git add -A'
alias gap='git add -p'
alias gc='git commit'
alias gcm='git commit -m'
alias gca='git commit --amend'
alias gcan='git commit --amend --no-edit'
alias gco='git checkout'
alias gsw='git switch'
alias gswc='git switch -c'
alias gf='git fetch --all --prune'
alias gp='git pull --rebase'
alias gP='git push'
alias gPu='git push -u origin HEAD'
alias gPf='git push --force-with-lease'

# Rebase
alias grb='git rebase'
alias grbi='git rebase -i'
alias grbia='git rebase -i --autosquash'
alias grbc='git rebase --continue'
alias grba='git rebase --abort'
alias grbs='git rebase --skip'

# Rebase on main (auto-detect)
grbm() {
  local base="$(_git_tools_default_base)"
  git fetch origin --prune
  git rebase "$base"
}

# Stash
alias gst='git stash'
alias gstp='git stash pop'

# Enhanced stash commands
alias gst-ls='git stash list --pretty=format:"%C(yellow)%gd%Creset %C(green)%cr%Creset %s"'

gst-show() {
  local stash="${1:-stash@{0}}"
  git stash show -p "$stash"
}

gst-drop() {
  local stash="${1:-stash@{0}}"
  _git_tools_confirm "Drop $stash?" || return 1
  git stash drop "$stash"
}

gst-save() {
  local msg="$1"
  [[ -z "$msg" ]] && { _git_tools_err "usage: gst-save <message>"; return 2; }
  git stash push -m "$msg"
}

# Diff
alias gdf='git diff'
alias gds='git diff --staged'
alias gdn='git diff --name-only'

# Reset
alias grh='git reset --hard'
alias grs='git reset --soft'
alias gundo='git reset --soft HEAD~1'

# Cherry-pick
alias gcp='git cherry-pick'
alias gcpc='git cherry-pick --continue'
alias gcpa='git cherry-pick --abort'

# Show/inspect
alias gsh='git show --stat'
alias gshf='git show'

# Reflog
alias grl='git reflog --pretty=format:"%C(yellow)%h%Creset %C(green)%gd%Creset %gs %C(dim)%cr%Creset"'
alias grlp='git reflog show --pretty=short'

# Tags
alias gt='git tag'
alias gtl='git tag -l --sort=-v:refname'

gta() {
  local tag="$1" msg="$2"
  [[ -z "$tag" ]] && { _git_tools_err "usage: gta <tag> [message]"; return 2; }
  if [[ -z "$msg" ]]; then
    git tag -a "$tag"
  else
    git tag -a "$tag" -m "$msg"
  fi
}

# Clean
gclean() {
  echo "Files to be removed:"
  git clean -dn
  _git_tools_confirm "Remove these files?" || return 1
  git clean -df
}

alias gclean-dry='git clean -dn'

# ============================================================================
# BRANCH MANAGEMENT
# ============================================================================

alias gbr-ls='git branch -vv'
alias gbr-merged='git branch --merged'
alias gbr-unmerged='git branch --no-merged'
alias gbr-remote='git branch -r'

gbr-newpush() {
  local branch="$1"
  local base="${2:-$(_git_tools_default_base)}"
  local remote="${3:-origin}"
  [[ -z "$branch" ]] && { _git_tools_err "usage: gbr-newpush <branch> [base] [remote]"; return 2; }

  _git_tools_in_git || { _git_tools_err "not in a git repo"; return 2; }

  git fetch --all --prune >/dev/null 2>&1 || true
  git switch -c "$branch" "$base" && git push -u "$remote" "$branch"
}

gbr-track() {
  local branch="$1" remote="${2:-origin}"
  [[ -z "$branch" ]] && { _git_tools_err "usage: gbr-track <branch> [remote]"; return 2; }
  _git_tools_in_git || { _git_tools_err "not in a git repo"; return 2; }

  git fetch "$remote" --prune || return 2

  if git show-ref --verify --quiet "refs/heads/$branch"; then
    git switch "$branch"
    return $?
  fi

  if git show-ref --verify --quiet "refs/remotes/$remote/$branch"; then
    git switch -c "$branch" --track "$remote/$branch"
    return $?
  fi

  _git_tools_err "remote branch not found: $remote/$branch"
  return 2
}

gbr-nuke() {
  _git_tools_parse_flags "$@"
  local branch="${__GT_ARGS[1]}" remote="${__GT_ARGS[2]:-origin}"
  [[ -z "$branch" ]] && { _git_tools_err "usage: gbr-nuke [--yes] [--safe|--unsafe] <branch> [remote]"; return 2; }

  local root="$(_git_tools_root)" || return
  local wt_dir="$root/$(_git_tools_dir_for_branch "$branch" "$root")"

  # Also check legacy path
  if [[ ! -d "$wt_dir" ]]; then
     local legacy="$root/${branch//\\//__}"
     [[ -d "$legacy" ]] && wt_dir="$legacy"
  fi

  if (( __GT_SAFE )); then
    if [[ "$branch" == "main" || "$branch" == "master" || "$branch" == "develop" ]]; then
      _git_tools_err "safe mode: refusing to delete protected branch: $branch (use --unsafe)"
      return 2
    fi
  fi

  print -r -- "About to delete branch:"
  print -r -- "  local : $branch"
  print -r -- "  remote: $remote/$branch"
  [[ -d "$wt_dir" ]] && print -r -- "  worktree: $wt_dir"

  if (( ! __GT_YES )); then
    _git_tools_confirm "Proceed?" || return 1
  fi

  if _git_tools_in_git; then
    local cur
    cur="$(git branch --show-current 2>/dev/null)"
    if [[ "$cur" == "$branch" ]]; then
      git switch "$(_git_tools_default_base)" || return 2
    fi
  fi

  (cd "$root" || return
    [[ -d "$wt_dir" ]] && git worktree remove "$wt_dir" >/dev/null 2>&1 || true
    git branch -D "$branch" >/dev/null 2>&1 || true
    git push "$remote" --delete "$branch" >/dev/null 2>&1 || true
    _git_tools_ok "deleted: $branch (local + $remote)"
  )
}

# ============================================================================
# REMOTES
# ============================================================================

gremote-ls() { git remote -v; }

gremote-add() {
  local name="$1" url="$2"
  [[ -z "$name" || -z "$url" ]] && { _git_tools_err "usage: gremote-add <name> <url>"; return 2; }
  git remote get-url "$name" >/dev/null 2>&1 && {
    _git_tools_err "remote '$name' already exists"; return 2
  }
  git remote add "$name" "$url" && _git_tools_ok "added remote '$name'"
}

gremote-gh() {
  local name="$1" repo="$2"
  [[ -z "$name" || -z "$repo" ]] && { _git_tools_err "usage: gremote-gh <name> <owner/repo>"; return 2; }
  command -v gh >/dev/null 2>&1 || { _git_tools_err "gh not found"; return 2; }
  local url
  url="$(gh repo view "$repo" --json sshUrl -q .sshUrl 2>/dev/null)" || {
    _git_tools_err "could not resolve $repo via gh"; return 2
  }
  gremote-add "$name" "$url"
}

# ============================================================================
# WORKTREE OPERATIONS
# ============================================================================

gwt-ls() {
  local root="$(_git_tools_root)" || return
  (cd "$root" && git worktree list)
}

gwt-prune() {
  local root="$(_git_tools_root)" || return
  (cd "$root" && git worktree prune && git worktree list)
}

gwt-add() {
  local branch="$1"
  [[ -z "$branch" ]] && { _git_tools_err "usage: gwt-add <branch>"; return 2; }

  local root="$(_git_tools_root)" || return
  local dir="$root/$(_git_tools_dir_for_branch "$branch" "$root")"

  (cd "$root" || return
    if [[ -e "$dir" ]]; then _git_tools_err "path exists: $dir"; return 2; fi

    if git show-ref --verify --quiet "refs/heads/$branch"; then
      git worktree add "$dir" "$branch"
    elif git show-ref --verify --quiet "refs/remotes/origin/$branch"; then
      git worktree add -b "$branch" "$dir" "origin/$branch"
    else
      _git_tools_err "branch not found locally or in origin: $branch"
      return 2
    fi
  )
}

gwt-new() {
  _git_tools_show_help "$1" 'gwt-new - Create new branch + worktree

USAGE:
  gwt-new <branch> [base]

ARGUMENTS:
  branch    New branch name (required)
  base      Base ref to branch from (default: origin/main or origin/master)

EXAMPLE:
  gwt-new feature/auth           # Branch from default base
  gwt-new fix/bug-123 v2.0.0     # Branch from tag
  gwt-new hotfix develop         # Branch from develop

NOTES:
  - Must be run from within a worktree or repo with .bare/ structure
  - Creates directory: {repo}-{branch} (slashes become __)
  - Example: gwt-new feature/login creates myrepo-feature__login/' && return 0

  local branch="$1"
  local base="${2:-$(_git_tools_default_base)}"
  [[ -z "$branch" ]] && { _git_tools_err "usage: gwt-new <branch> [base]"; return 2; }

  local root="$(_git_tools_root)" || return
  local dir="$root/$(_git_tools_dir_for_branch "$branch" "$root")"

  (cd "$root" || return
    [[ -e "$dir" ]] && { _git_tools_err "path exists: $dir"; return 2; }
    git worktree add -b "$branch" "$dir" "$base"
  )
}

gwt-newpush() {
  local branch="$1"
  local base="${2:-$(_git_tools_default_base)}"
  local remote="${3:-origin}"
  [[ -z "$branch" ]] && { _git_tools_err "usage: gwt-newpush <branch> [base] [remote]"; return 2; }

  gwt-new "$branch" "$base" || return
  local root="$(_git_tools_root)" || return
  local dir="$root/$(_git_tools_dir_for_branch "$branch" "$root")"
  git -C "$dir" push -u "$remote" "$branch"
}

gwt-rm() {
  local target="$1"
  [[ -z "$target" ]] && { _git_tools_err "usage: gwt-rm <worktree-path>"; return 2; }

  local root="$(_git_tools_root)" || return
  local path="$target"
  [[ "$path" != /* ]] && path="$root/$target"

  (cd "$root" || return
    git worktree remove "$path"
  )
}

gwt-go() {
  _git_tools_show_help "$1" 'gwt-go - Switch to worktree directory

USAGE:
  gwt-go <branch>

ARGUMENTS:
  branch    Branch name of the worktree to switch to

EXAMPLE:
  gwt-go main              # Switch to main worktree
  gwt-go feature/auth      # Switch to feature branch worktree

NOTES:
  - Changes current directory to the worktree
  - Use gwf (gwt-fzf) for interactive selection with fzf
  - Supports both new naming (repo-branch) and legacy naming' && return 0

  local branch="$1"
  [[ -z "$branch" ]] && { _git_tools_err "usage: gwt-go <branch>"; return 2; }
  local root="$(_git_tools_root)" || return
  local dir="$root/$(_git_tools_dir_for_branch "$branch" "$root")"
  
  # Support for legacy naming
  if [[ ! -d "$dir" ]]; then
    local legacy="$root/${branch//\\//__}"
    if [[ -d "$legacy" ]]; then dir="$legacy"; fi
  fi
  
  [[ -d "$dir" ]] || { _git_tools_err "not found: $dir"; return 2; }
  cd "$dir"
}

gwt-repair() {
  local root="$(_git_tools_root)" || return
  (cd "$root" && git worktree repair)
}

gwt-lock() {
  local target="$1"
  [[ -z "$target" ]] && { _git_tools_err "usage: gwt-lock <worktree>"; return 2; }
  local root="$(_git_tools_root)" || return
  local path="$target"
  [[ "$path" != /* ]] && path="$root/$target"
  git worktree lock "$path"
}

gwt-unlock() {
  local target="$1"
  [[ -z "$target" ]] && { _git_tools_err "usage: gwt-unlock <worktree>"; return 2; }
  local root="$(_git_tools_root)" || return
  local path="$target"
  [[ "$path" != /* ]] && path="$root/$target"
  git worktree unlock "$path"
}

gwt-sync() {
  local root="$(_git_tools_root)" || return
  echo "Fetching all remotes..."
  git -C "$root/.bare" fetch --all --prune
  echo ""
  echo "Worktree status:"
  gwt-status-all
}

gwt-status-all() {
  local root="$(_git_tools_root)" || return
  git -C "$root" worktree list --porcelain | grep '^worktree' | cut -d' ' -f2 | while read wt; do
    echo "=== ${wt##*/} ==="
    git -C "$wt" status -sb 2>/dev/null || echo "(not accessible)"
    echo ""
  done
}

gwt-rebase-all() {
  local root="$(_git_tools_root)" || return
  local base="origin/main"
  
  # Ensure we have the latest info
  print -r -- "Fetching updates..."
  git -C "$root/.bare" fetch --all --prune
  
  # Check if main/master exists in remotes
  if ! git -C "$root/.bare" show-ref --verify --quiet "refs/remotes/$base"; then
    base="origin/master"
  fi

  print -r -- "Propagating $base to all worktrees..."
  print -r -- "========================================"

  local worktrees
  worktrees=("${(@f)$(git -C "$root" worktree list --porcelain | grep '^worktree' | cut -d' ' -f2)}")

  for wt in $worktrees; do
    local branch
    branch="$(git -C "$wt" branch --show-current)"
    [[ -z "$branch" ]] && continue
    
    # Skip if we are on the main branch itself
    if [[ "$base" == *"$branch" ]]; then
      continue
    fi
    
    print -r -- "Processing: $branch ($wt)"
    (
      cd "$wt" || return
      # Rebase
      if git rebase "$base"; then
        # Push safe force
        if git push --force-with-lease; then
          print -r -- "  ✓ Updated"
        else
          _git_tools_err "  ✗ Push failed"
        fi
      else
        _git_tools_err "  ✗ Rebase failed (conflict?). Fix manually in: $wt"
        return 1
      fi
    ) || return 1 # Stop on first failure
  done
  
  print -r -- "========================================"
  _git_tools_ok "All done."
}

# FZF integration for worktrees
if command -v fzf >/dev/null 2>&1; then
  gwt-fzf() {
    local root="$(_git_tools_root)" || return
    local selection
    selection=$(git -C "$root" worktree list --porcelain | \
      grep '^worktree' | cut -d' ' -f2 | \
      fzf --height=40% --reverse --preview 'git -C {} status -sb') || return
    cd "$selection"
  }
  alias gwf='gwt-fzf'
fi

# ============================================================================
# REPO INIT (bare layout)
# ============================================================================

gwt-init-bare() {
  local url="$1"
  local dir="${2:-}"
  [[ -z "$url" ]] && { _git_tools_err "usage: gwt-init-bare <git-url> [dir]"; return 2; }

  if [[ -z "$dir" ]]; then
    dir="${${url:t}%.git}"
  fi

  mkdir -p "$dir" || return 2
  (cd "$dir" || return
    git clone --bare "$url" .bare || return 2
    print -r -- "gitdir: ./.bare" > .git
    git config remote.origin.fetch "+refs/heads/*:refs/remotes/origin/*"
    git fetch origin
    local first="main"
    if git show-ref --verify --quiet refs/remotes/origin/main; then first="main"
    elif git show-ref --verify --quiet refs/remotes/origin/master; then first="master"
    fi
    local wt_dir
    wt_dir="$(_git_tools_dir_for_branch "$first" "$(pwd)")"
    git worktree add "$first" "origin/$first" 2>/dev/null || git worktree add "$wt_dir" "$first"
    _git_tools_ok "ready: $dir/$first"
  )
}

gwt-init-empty() {
  _git_tools_parse_flags "$@"
  local dir="${__GT_ARGS[1]}" branch="${__GT_ARGS[2]:-main}"
  [[ -z "$dir" ]] && { _git_tools_err "usage: gwt-init-empty [--yes] <dir> [branch]"; return 2; }

  mkdir -p "$dir" || return 2

  if (( __GT_SAFE )); then
    _git_tools_dir_empty "$dir" || { _git_tools_err "safe mode: directory not empty: $dir"; return 2; }
  fi

  if (( ! __GT_YES )); then
    _git_tools_confirm "Initialize .bare repo in '$dir'?" || return 1
  fi

  cd "$dir" || return 2
  [[ -d .bare || -e .git ]] && { _git_tools_err "already initialized here"; return 2; }

  git init || return 2
  git branch -M "$branch" || return 2
  [[ -f README.md ]] || print -r -- "# ${dir:t}" > README.md
  git add -A && git commit -m "chore: initial commit" || return 2

  git clone --bare . .bare || return 2
  
  # CRITICAL FIX: Remove the 'origin' remote that points to the local filesystem
  # This prevents 'gh' and other tools from getting confused by circular refs
  git -C .bare remote remove origin 2>/dev/null

  rm -rf .git
  print -r -- "gitdir: ./.bare" > .git

  local wt_dir
  wt_dir="$(_git_tools_dir_for_branch "$branch" "$(pwd)")"
  git worktree add "$wt_dir" "$branch" || return 2

  _git_tools_ok "ready: $(pwd)/$wt_dir"
}

gwt-ship() {
  _git_tools_show_help "$1" 'gwt-ship - Initialize repo + GitHub remote + push (all-in-one)

USAGE:
  gwt-ship <repo-name> [branch]

ARGUMENTS:
  repo-name   Name for the new repository (required)
  branch      Initial branch name (default: main)

EXAMPLE:
  gwt-ship myproject main    # Creates myproject with main branch, pushes to GitHub
  gwt-ship api-server        # Creates api-server with default main branch

NOTES:
  - Requires GitHub CLI (gh) to be installed and authenticated
  - Creates a private repository by default
  - Uses bare repository layout with worktrees
  - Creates directory structure: myproject/.bare/ + myproject/myproject-main/' && return 0

  local name="$1"
  local branch="${2:-main}"
  [[ -z "$name" ]] && { _git_tools_err "usage: gwt-ship <repo-name> [branch-name]"; return 2; }
  
  command -v gh >/dev/null 2>&1 || { _git_tools_err "gh not found. install github cli."; return 2; }

  # 1. Create (or find) GitHub repo first
  # We do this independent of local state to avoid 'gh' getting confused by worktrees
  local repo_url
  if gh repo view "$name" >/dev/null 2>&1; then
    print -r -- "Repository '$name' already exists on GitHub. Using it."
  else
    print -r -- "Creating GitHub repository '$name'..."
    gh repo create "$name" --private || return 1
  fi
  
  # Detect user's preferred protocol (ssh vs https)
  local proto
  proto="$(gh config get git_protocol 2>/dev/null)"
  if [[ "$proto" == "ssh" ]]; then
    repo_url="$(gh repo view "$name" --json sshUrl -q .sshUrl)"
  else
    repo_url="$(gh repo view "$name" --json url -q .url)"
  fi
  
  [[ -z "$repo_url" ]] && return 1

  # 2. Initialize local repo structure
  # This changes directory to the new repo root
  gwt-init-empty --yes "$name" "$branch" || return 1
  
  # 3. Find worktree directory
  local root="$(pwd)"
  local wt_dir="$root/$(_git_tools_dir_for_branch "$branch" "$root")"
  
  if [[ ! -d "$wt_dir" ]]; then
     _git_tools_err "could not find worktree dir: $wt_dir"
     return 1
  fi
  
  # 4. Configure remote and push
  (cd "$wt_dir" || return 1
    git remote add origin "$repo_url" || return 1
    git config remote.origin.fetch "+refs/heads/*:refs/remotes/origin/*"

    print -r -- "Pushing to GitHub..."
    git push -u origin "$branch"
  ) || return 1
  
  _git_tools_ok "shipped: $name ($branch) -> GitHub"
  _git_tools_ok "  repo root: $root"
  _git_tools_ok "  worktree:  $wt_dir"
}

gwt-clone-bare() {
  _git_tools_show_help "$1" 'gwt-clone-bare - Clone existing repo into bare structure

USAGE:
  gwt-clone-bare [--yes] [--safe|--unsafe] <url> [dir] [branch]

ARGUMENTS:
  url       Git repository URL (required)
  dir       Target directory (default: derived from URL)
  branch    Initial branch to checkout (default: main)

FLAGS:
  --yes     Skip confirmation prompts
  --safe    Require empty directory (default)
  --unsafe  Allow non-empty directory

EXAMPLE:
  gwt-clone-bare git@github.com:user/repo.git
  gwt-clone-bare https://github.com/user/repo.git myrepo
  gwt-clone-bare --yes git@github.com:user/repo.git . main

NOTES:
  - Creates .bare/ directory with bare clone
  - Sets up proper fetch refspec for all branches
  - Creates initial worktree for specified branch' && return 0

  _git_tools_parse_flags "$@"
  local url="${__GT_ARGS[1]}" dir="${__GT_ARGS[2]}" branch="${__GT_ARGS[3]:-main}"
  [[ -z "$url" ]] && { _git_tools_err "usage: gwt-clone-bare [--yes] <url> [dir] [branch]"; return 2; }

  if [[ -n "$dir" ]]; then
    mkdir -p "$dir" || return 2
    if (( __GT_SAFE )); then
      _git_tools_dir_empty "$dir" || { _git_tools_err "safe mode: directory not empty: $dir"; return 2; }
    fi
    if (( ! __GT_YES )); then
      _git_tools_confirm "Clone into '$dir'?" || return 1
    fi
    cd "$dir" || return 2
  else
    if (( __GT_SAFE )); then
      _git_tools_dir_empty "$PWD" || { _git_tools_err "safe mode: current directory not empty"; return 2; }
    fi
    if (( ! __GT_YES )); then
      _git_tools_confirm "Clone into '$PWD'?" || return 1
    fi
  fi

  [[ -d .bare || -e .git ]] && { _git_tools_err "already initialized here"; return 2; }

  git clone --bare "$url" .bare || return 2
  print -r -- "gitdir: ./.bare" > .git
  git config remote.origin.fetch "+refs/heads/*:refs/remotes/origin/*"
  git fetch origin || return 2

  if git show-ref --verify --quiet "refs/remotes/origin/$branch"; then
    git worktree add "$branch" "origin/$branch" || return 2
  elif git show-ref --verify --quiet "refs/remotes/origin/master"; then
    git worktree add master origin/master || return 2
    branch="master"
  else
    _git_tools_err "could not find origin/$branch or origin/master"
    return 2
  fi

  _git_tools_ok "ready: $(pwd)/$branch"
}

# ============================================================================
# SEARCH HELPERS
# ============================================================================

ghelp-grep() {
  local pat="$1"
  [[ -z "$pat" ]] && { _git_tools_err "usage: ghelp-grep <pattern>"; return 2; }
  ghelp | command grep -i -- "$pat"
}

galiases() {
  alias | command grep -E '^(g|gs|gl|ga|gc|gco|gsw|gf|gp|gP|grb|gst|gdf|gds|grh|gcp)='
}
