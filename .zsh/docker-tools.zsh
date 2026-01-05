# docker-tools.zsh - Docker & Docker Compose power-user aliases
# Run 'dkhelp' for available commands

# ============================================================================
# HELPERS
# ============================================================================

_docker_tools_show_help() {
  case "$1" in -h|--help) printf '%s\n' "$2"; return 0 ;; esac
  return 1
}

# ============================================================================
# HELP SYSTEM
# ============================================================================

dkhelp() {
  cat <<'EOF'
Docker Tools - Available Commands
==================================

CONTAINER MANAGEMENT:
  dkps           List running containers (formatted)
  dkpsa          List ALL containers (formatted)
  dkrm <id>      Remove container(s)
  dkrmall        Remove ALL containers (running + stopped)
  dkrmgrep <s>   Remove containers matching pattern
  dkstop <id>    Stop container(s)
  dkstopall      Stop all running containers
  dkstart <id>   Start container(s)
  dkrestart <id> Restart container(s)

CONTAINER INSPECTION & INTERACTION:
  dklogs <id>    Show container logs (follow)
  dklogst <id>   Show container logs with timestamps
  dkexec <id>    Execute bash/sh in running container
  dksh <id>      Alias for dkexec
  dkinspect <id> Inspect container
  dktop <id>     Show container processes
  dkstats        Show live container stats

VOLUME MANAGEMENT:
  dkvls          List all volumes
  dkvrm <name>   Remove volume(s)
  dkvrmall       Remove ALL volumes
  dkvrmgrep <s>  Remove volumes matching pattern
  dkvinspect <n> Inspect volume

IMAGE MANAGEMENT:
  dkimg          List images (formatted)
  dkimghist <id> Show image layers/history
  dkrmi <id>     Remove image(s)
  dkrmidangling  Remove dangling images
  dkpull <img>   Pull image
  dkbuild        Build image

NETWORK MANAGEMENT:
  dknet          List networks
  dknetinspect   Inspect network
  dknetrm <name> Remove network(s)
  dknetprune     Remove unused networks

CLEANUP OPERATIONS:
  dkclean        Remove stopped containers + dangling images
  dkprune        Prune system (keep images)
  dkpruneall     Full system prune (everything unused)
  dkcleanup      Interactive cleanup wizard
  dkdf           Show docker disk usage

DOCKER COMPOSE:
  dc             docker compose
  dcu            docker compose up
  dcud           docker compose up -d
  dcd            docker compose down
  dcdv           docker compose down -v (remove volumes)
  dcl            docker compose logs -f
  dcls <svc>     docker compose logs -f <service>
  dcr            docker compose restart
  dcb            docker compose build
  dcbn           docker compose build --no-cache
  dce <svc>      docker compose exec <service>
  dcsh <svc>     docker compose exec <service> bash/sh
  dcps           docker compose ps
  dcpull         docker compose pull
  dcstop         docker compose stop
  dcstart        docker compose start
  dcrs <svc>     Rebuild and restart service

UTILITY:
  dkip <id>      Get container IP address
  dkport <id>    Show container port mappings
  dksize         Show container sizes
  dkenv <id>     Show container environment variables

Run 'dkhelp' anytime to show this help.
EOF
}

# ============================================================================
# CONTAINER MANAGEMENT
# ============================================================================

# Listing
alias dkps='docker ps --format "table {{.ID}}\t{{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"'
alias dkpsa='docker ps -a --format "table {{.ID}}\t{{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"'

# Basic operations
alias dkrm='docker rm'
alias dkstop='docker stop'
alias dkstart='docker start'
alias dkrestart='docker restart'

# Stop all running containers
dkstopall() {
  local containers=$(docker ps -q)
  if [[ -z "$containers" ]]; then
    echo "No running containers to stop."
    return 0
  fi
  echo "Stopping $(echo $containers | wc -w | tr -d ' ') containers..."
  docker stop $containers
}

# Remove ALL containers
function dkrmall {
  local containers=$(docker ps -aq)
  if [[ -z "$containers" ]]; then
    echo "No containers to remove."
    return 0
  fi
  echo "Removing $(echo $containers | wc -w | tr -d ' ') containers..."
  docker rm -f $containers
}

# Remove containers matching pattern
function dkrmgrep {
  local pat="$1"
  [[ -z "$pat" ]] && echo "Usage: dkrmgrep <pattern>" && return 1

  local matches=$(docker ps -a --format '{{.ID}} {{.Names}}' | grep -i "$pat")
  if [[ -z "$matches" ]]; then
    echo "No containers matching '$pat'"
    return 0
  fi

  echo "Containers to remove:"
  echo "$matches"
  echo ""
  echo "$matches" | awk '{print $1}' | xargs docker rm -f
}

# ============================================================================
# CONTAINER INSPECTION & INTERACTION
# ============================================================================

# Logs
alias dklogs='docker logs -f'
alias dklogst='docker logs -f -t'

# Execute shell in container
dkexec() {
  _docker_tools_show_help "$1" 'dkexec - Execute interactive shell in a running container

USAGE:
  dkexec <container>

ARGUMENTS:
  container   Container ID or name (required)

EXAMPLE:
  dkexec my-app           # Open shell in container named my-app
  dkexec abc123           # Open shell in container by ID
  dkexec $(dkps -q | head -1)  # Open shell in first running container

NOTES:
  - Tries bash first, falls back to sh if bash unavailable
  - Use dkshf for fuzzy-find selection with fzf
  - Alias: dksh' && return 0

  local container="$1"
  [[ -z "$container" ]] && echo "Usage: dkexec <container>" && return 1

  # Try bash first, fall back to sh
  docker exec -it "$container" bash 2>/dev/null || docker exec -it "$container" sh
}
alias dksh='dkexec'

# Inspection
alias dkinspect='docker inspect'
alias dktop='docker top'
alias dkstats='docker stats'

# Get container IP
dkip() {
  local container="$1"
  [[ -z "$container" ]] && echo "Usage: dkip <container>" && return 1
  docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$container"
}

# Show port mappings
alias dkport='docker port'

# Show container sizes
dksize() {
  docker ps -s --format "table {{.Names}}\t{{.Size}}"
}

# Show container environment variables
dkenv() {
  local container="$1"
  [[ -z "$container" ]] && echo "Usage: dkenv <container>" && return 1
  docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$container"
}

# ============================================================================
# VOLUME MANAGEMENT
# ============================================================================

alias dkvls='docker volume ls'
alias dkvrm='docker volume rm'
alias dkvinspect='docker volume inspect'

# Remove ALL volumes
function dkvrmall {
  local volumes=$(docker volume ls -q)
  if [[ -z "$volumes" ]]; then
    echo "No volumes to remove."
    return 0
  fi
  echo "Removing $(echo $volumes | wc -w | tr -d ' ') volumes..."
  docker volume rm $volumes 2>&1 | grep -v "volume is in use" || true
}

# Remove volumes matching pattern
function dkvrmgrep {
  local pat="$1"
  [[ -z "$pat" ]] && echo "Usage: dkvrmgrep <pattern>" && return 1

  local volumes=$(docker volume ls --format '{{.Name}}' | grep -i "$pat")
  if [[ -z "$volumes" ]]; then
    echo "No volumes matching '$pat'"
    return 0
  fi

  echo "Volumes to remove:"
  echo "$volumes"
  echo ""
  echo "$volumes" | xargs docker volume rm
}

# ============================================================================
# IMAGE MANAGEMENT
# ============================================================================

alias dkimg='docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.Size}}\t{{.CreatedSince}}"'
alias dkrmi='docker rmi'
alias dkpull='docker pull'
alias dkbuild='docker build'

# Show image layers/history
dkimghist() {
  local image="$1"
  [[ -z "$image" ]] && echo "Usage: dkimghist <image>" && return 1
  docker history "$image" --human
}

# Remove dangling images
function dkrmidangling {
  local dangling=$(docker images -f "dangling=true" -q)
  if [[ -z "$dangling" ]]; then
    echo "No dangling images to remove."
    return 0
  fi
  echo "Removing dangling images..."
  docker rmi $dangling
}

# ============================================================================
# NETWORK MANAGEMENT
# ============================================================================

alias dknet='docker network ls'
alias dknetinspect='docker network inspect'
alias dknetrm='docker network rm'
alias dknetprune='docker network prune -f'

# ============================================================================
# CLEANUP OPERATIONS
# ============================================================================

# Show disk usage
alias dkdf='docker system df'

# Clean stopped containers and dangling images
dkclean() {
  echo "Removing stopped containers..."
  docker container prune -f
  echo "Removing dangling images..."
  docker image prune -f
  echo ""
  docker system df
}

# Prune system but keep images
dkprune() {
  echo "Pruning system (keeping images)..."
  docker system prune -f
  echo ""
  docker system df
}

# Full system prune
function dkpruneall {
  echo "Full system prune - removing all unused images, networks, volumes..."
  docker system prune -a --volumes -f
  echo ""
  docker system df
}

# Interactive cleanup wizard
dkcleanup() {
  echo "Docker Cleanup Wizard"
  echo "====================="
  echo ""

  # Show current usage
  docker system df
  echo ""

  # Stopped containers
  local stopped=$(docker ps -aq -f status=exited 2>/dev/null)
  if [[ -n "$stopped" ]]; then
    echo "Found $(echo $stopped | wc -w | tr -d ' ') stopped containers"
    read "answer?Remove stopped containers? [y/N] "
    [[ "$answer" =~ ^[Yy]$ ]] && docker container prune -f
    echo ""
  fi

  # Dangling images
  local dangling=$(docker images -f "dangling=true" -q 2>/dev/null)
  if [[ -n "$dangling" ]]; then
    echo "Found $(echo $dangling | wc -w | tr -d ' ') dangling images"
    read "answer?Remove dangling images? [y/N] "
    [[ "$answer" =~ ^[Yy]$ ]] && docker image prune -f
    echo ""
  fi

  # Unused networks
  read "answer?Prune unused networks? [y/N] "
  [[ "$answer" =~ ^[Yy]$ ]] && docker network prune -f
  echo ""

  # Unused volumes
  local unused_vols=$(docker volume ls -qf dangling=true 2>/dev/null)
  if [[ -n "$unused_vols" ]]; then
    echo "Found $(echo $unused_vols | wc -w | tr -d ' ') unused volumes"
    read "answer?Remove unused volumes? [y/N] "
    [[ "$answer" =~ ^[Yy]$ ]] && docker volume prune -f
    echo ""
  fi

  echo "Cleanup complete!"
  docker system df
}

# ============================================================================
# DOCKER COMPOSE
# ============================================================================

alias dc='docker compose'
alias dcu='docker compose up'
alias dcud='docker compose up -d'
alias dcd='docker compose down'
alias dcdv='docker compose down -v'
alias dcl='docker compose logs -f'
alias dcr='docker compose restart'
alias dcb='docker compose build'
alias dcbn='docker compose build --no-cache'
alias dce='docker compose exec'
alias dcps='docker compose ps'
alias dcpull='docker compose pull'
alias dcstop='docker compose stop'
alias dcstart='docker compose start'

# Compose logs for specific service
dcls() {
  local service="$1"
  [[ -z "$service" ]] && echo "Usage: dcls <service>" && return 1
  docker compose logs -f "$service"
}

# Compose exec with shell (auto-detects bash/sh)
dcsh() {
  _docker_tools_show_help "$1" 'dcsh - Execute shell in docker compose service

USAGE:
  dcsh [service]

ARGUMENTS:
  service   Service name (optional if only one service running)

EXAMPLE:
  dcsh web              # Open shell in web service
  dcsh                  # Auto-detect if only one service running
  dcsh api              # Open shell in api service

NOTES:
  - Auto-detects service if only one is running
  - Tries bash first, falls back to sh if bash unavailable
  - Must be run from directory with docker-compose.yml' && return 0

  local service="$1"
  if [[ -z "$service" ]]; then
    # Try to auto-detect if only one service is running
    local services=$(docker compose ps --services --filter "status=running" 2>/dev/null)
    local count=$(echo "$services" | grep -c .)
    if [[ $count -eq 1 ]]; then
      service="$services"
      echo "Auto-detected service: $service"
    else
      echo "Usage: dcsh <service>"
      echo "Running services:"
      docker compose ps --services --filter "status=running" 2>/dev/null
      return 1
    fi
  fi

  docker compose exec "$service" bash 2>/dev/null || docker compose exec "$service" sh
}

# Rebuild and restart specific service
dcrs() {
  local service="$1"
  [[ -z "$service" ]] && echo "Usage: dcrs <service>" && return 1
  docker compose up -d --build "$service"
}

# Compose with specific file
dcf() {
  local file="$1"
  shift
  [[ -z "$file" ]] && echo "Usage: dcf <compose-file> <command...>" && return 1
  docker compose -f "$file" "$@"
}

# ============================================================================
# FZF INTEGRATION (if fzf is available)
# ============================================================================

if command -v fzf >/dev/null 2>&1; then
  # Fuzzy-find container and exec into it
  dkshf() {
    local container=$(docker ps --format '{{.ID}}\t{{.Names}}\t{{.Image}}' | \
      fzf --header="Select container" | awk '{print $1}')
    [[ -n "$container" ]] && dkexec "$container"
  }

  # Fuzzy-find container and show logs
  dklogsf() {
    local container=$(docker ps -a --format '{{.ID}}\t{{.Names}}\t{{.Image}}' | \
      fzf --header="Select container" | awk '{print $1}')
    [[ -n "$container" ]] && docker logs -f "$container"
  }

  # Fuzzy-find and remove containers
  dkrmf() {
    local containers=$(docker ps -a --format '{{.ID}}\t{{.Names}}\t{{.Image}}\t{{.Status}}' | \
      fzf -m --header="Select containers to remove (TAB for multi)" | awk '{print $1}')
    [[ -n "$containers" ]] && echo "$containers" | xargs docker rm -f
  }
fi
