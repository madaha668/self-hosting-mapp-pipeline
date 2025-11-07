#!/usr/bin/env bash
#
# GitLab Runner Registration Script
# Registers runners using authentication tokens (modern workflow)
# Supports both local installation and Docker deployment
#
# Usage: ./register_gitlab_runner.sh [options]
#

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${LOG_FILE:-/var/log/gitlab_runner_registration.log}"
GITLAB_URL="${GITLAB_URL:-https://gitlab.example.com}"
RUNNER_TOKEN="${RUNNER_TOKEN:-}"
DRY_RUN=false
VERBOSE=false
YES=false

# Runner registration options
RUNNER_NAME=""
RUNNER_EXECUTOR="docker"
DOCKER_IMAGE="alpine:latest"
DOCKER_VOLUMES=""
DOCKER_PRIVILEGED=false
RUNNER_CONCURRENCY=1
REQUEST_CONCURRENCY=1
MAINTENANCE_NOTE=""

# Deployment method
DEPLOY_METHOD="local"  # local or docker
SERVICE_NAME="gitlab-runner"

# ============================================================================
# Logging and Output
# ============================================================================

# Ensure we have a writable logfile
if ! { mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null && touch "$LOG_FILE" 2>/dev/null; }; then
  LOG_FILE="$SCRIPT_DIR/gitlab_runner_registration.log"
  mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
  touch "$LOG_FILE" 2>/dev/null || true
fi

_log() {
  local level="$1"; shift
  local message="$*"
  local timestamp
  timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  printf '[%s] [%s] %s\n' "$timestamp" "$level" "$message" >>"$LOG_FILE" 2>/dev/null || true
  if [[ "$VERBOSE" == true || "$level" == "ERROR" || "$level" == "WARN" ]]; then
    printf '[%s] %s\n' "$level" "$message" >&2
  fi
}

info()    { _log "INFO"    "$*"; }
success() { _log "INFO"    "$*"; echo "✓ $*"; }
error()   { _log "ERROR"   "$*"; echo "✗ ERROR: $*" >&2; }
warn()    { _log "WARN"    "$*"; echo "⚠ WARNING: $*" >&2; }

# ============================================================================
# Validation Functions
# ============================================================================

validate_url() {
  local url="$1"
  if [[ ! "$url" =~ ^https?:// ]]; then
    error "Invalid URL: must start with http:// or https://"
    return 1
  fi
  info "GitLab URL validated: $url"
  return 0
}

validate_token() {
  local token="$1"
  if [[ -z "$token" ]]; then
    error "Runner token cannot be empty"
    return 1
  fi
  if [[ ! "$token" =~ ^glrt- ]]; then
    warn "Token does not start with 'glrt-' - make sure it's a runner authentication token"
  fi
  info "Runner token validated"
  return 0
}

validate_runner_name() {
  local name="$1"
  if [[ -z "$name" ]]; then
    error "Runner name cannot be empty"
    return 1
  fi
  if [[ ! "$name" =~ ^[a-zA-Z0-9_-]{1,255}$ ]]; then
    error "Invalid runner name: must be 1-255 chars of [a-zA-Z0-9_-]"
    return 1
  fi
  info "Runner name validated: $name"
  return 0
}

# ============================================================================
# Prerequisite Checks
# ============================================================================

check_prerequisites() {
  if [[ "$DEPLOY_METHOD" == "local" ]]; then
    # Check for local gitlab-runner installation
    if ! command -v gitlab-runner &>/dev/null; then
      error "gitlab-runner is not installed. Install it with:"
      error "  Ubuntu/Debian: sudo apt-get install gitlab-runner"
      error "  CentOS/RHEL: sudo yum install gitlab-runner"
      return 1
    fi
    info "gitlab-runner found: $(gitlab-runner --version)"
  elif [[ "$DEPLOY_METHOD" == "docker" ]]; then
    # Check for docker
    if ! command -v docker &>/dev/null; then
      error "Docker is not installed or not in PATH"
      return 1
    fi
    info "Docker found: $(docker --version)"
  fi

  info "All prerequisites met for deployment method: $DEPLOY_METHOD"
  return 0
}

# ============================================================================
# Runner Registration (Local)
# ============================================================================

register_runner_local() {
  local name="$1" token="$2" url="$3" executor="$4"

  info "Registering runner locally: $name"

  if [[ "$DRY_RUN" == true ]]; then
    info "(Dry run mode) Would register runner with:"
    info "  Name: $name"
    info "  URL: $url"
    info "  Executor: $executor"
    info "  Docker Image: $DOCKER_IMAGE"
    return 0
  fi

  # Build registration command
  local cmd=(
    "gitlab-runner" "register"
    "--non-interactive"
    "--name" "$name"
    "--url" "$url"
    "--token" "$token"
    "--executor" "$executor"
  )

  # Add executor-specific options
  if [[ "$executor" == "docker" ]]; then
    cmd+=("--docker-image" "$DOCKER_IMAGE")
    if [[ -n "$DOCKER_VOLUMES" ]]; then
      cmd+=("--docker-volumes" "$DOCKER_VOLUMES")
    fi
    if [[ "$DOCKER_PRIVILEGED" == true ]]; then
      cmd+=("--docker-privileged")
    fi
  fi

  cmd+=(
    "--request-concurrency" "$REQUEST_CONCURRENCY"
    "--builds-dir" "${HOME}/ci-cd/working/builds"
    "--cache-dir" "${HOME}/ci-cd/working/cache"
  )

  info "Executing registration command..."
  if ! "${cmd[@]}"; then
    error "Failed to register runner"
    return 1
  fi

  success "Runner registered successfully"
  info "Runner '$name' is now registered and should appear in GitLab UI"
  info "Restart the runner service: sudo systemctl restart $SERVICE_NAME"
  return 0
}

# ============================================================================
# Runner Registration (Docker)
# ============================================================================

register_runner_docker() {
  local name="$1" token="$2" url="$3" executor="$4"

  info "Registering runner in Docker: $name"

  if [[ "$DRY_RUN" == true ]]; then
    info "(Dry run mode) Would deploy runner in Docker with:"
    info "  Name: $name"
    info "  URL: $url"
    info "  Executor: $executor"
    return 0
  fi

  # Create config.toml entry
  local config_dir="${HOME}/.gitlab-runner"
  mkdir -p "$config_dir"

  local config_file="$config_dir/config.toml"
  
  # Check if config exists, if not create template
  if [[ ! -f "$config_file" ]]; then
    cat > "$config_file" <<'EOF'
concurrent = 4
check_interval = 0
shutdown_timeout = 0

[session_server]
  session_timeout = 1800

EOF
  fi

  # Add runner entry
  cat >> "$config_file" <<RUNNER_CONFIG

[[runners]]
  name = "$name"
  url = "$url"
  token = "glrt-PLACEHOLDER"
  id = 0
  token_expiration_interval = 0s
  output_limit = 4194304
  executor = "$executor"
  builds_dir = ""
  cache_dir = ""
  [runners.cache]
    [runners.cache.s3]
    [runners.cache.gcs]
    [runners.cache.azure]
RUNNER_CONFIG

  warn "Docker runner configuration requires manual setup"
  info "Configuration template created at: $config_file"
  info "You must edit $config_file and add your runner token to the [runners] section"
  info "Then mount this config file when running the gitlab-runner Docker container"
  return 0
}

# ============================================================================
# Argument Parsing
# ============================================================================

show_usage() {
  cat <<EOF
Usage: $0 [options]

Registers a GitLab runner with an authentication token

Options:
  -u, --url <url>               GitLab instance URL (default: https://gitlab.example.com)
  -t, --token <token>           Runner authentication token (glrt-xxx)
  -n, --name <name>             Runner name/hostname (required)
  -e, --executor <type>         Executor type: docker, shell, kubernetes (default: docker)
  -i, --docker-image <image>    Docker image for docker executor (default: alpine:latest)
  -v, --docker-volumes <vols>   Docker volumes (e.g., "/var/run/docker.sock:/var/run/docker.sock")
  --docker-privileged           Run Docker container in privileged mode
  -c, --concurrency <n>         Number of builds to run concurrently (default: 1)
  -r, --request-concurrency <n> Request concurrency limit (default: 1)
  --deploy-method <method>      Deployment: local or docker (default: local)
  --service-name <name>         Systemd service name (default: gitlab-runner)
  --dry-run                     Show what would be done
  -y, --yes                     Skip confirmation
  -v, --verbose                 Verbose output
  -h, --help                    Show this help message

Environment Variables:
  GITLAB_URL                    GitLab instance URL
  GITLAB_TOKEN                  Runner authentication token

Examples:
  # Interactive registration
  $0

  # Local Docker executor runner
  $0 -t 'glrt-xxx' -u https://gitlab.example.com -n 'docker-runner-1' -e docker

  # Shell executor runner
  $0 -t 'glrt-xxx' -n 'shell-runner-1' -e shell

  # Privileged Docker runner (for Docker-in-Docker)
  $0 -t 'glrt-xxx' -n 'dind-runner' -e docker --docker-privileged

EOF
}

parse_arguments() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        show_usage; exit 0 ;;
      -u|--url)
        GITLAB_URL="$2"; shift 2 ;;
      -t|--token)
        RUNNER_TOKEN="$2"; shift 2 ;;
      -n|--name)
        RUNNER_NAME="$2"; shift 2 ;;
      -e|--executor)
        RUNNER_EXECUTOR="$2"; shift 2 ;;
      -i|--docker-image)
        DOCKER_IMAGE="$2"; shift 2 ;;
      -V|--docker-volumes)
        DOCKER_VOLUMES="$2"; shift 2 ;;
      --docker-privileged)
        DOCKER_PRIVILEGED=true; shift ;;
      -c|--concurrency)
        RUNNER_CONCURRENCY="$2"; shift 2 ;;
      -r|--request-concurrency)
        REQUEST_CONCURRENCY="$2"; shift 2 ;;
      --deploy-method)
        DEPLOY_METHOD="$2"; shift 2 ;;
      --service-name)
        SERVICE_NAME="$2"; shift 2 ;;
      --dry-run)
        DRY_RUN=true; shift ;;
      -y|--yes)
        YES=true; shift ;;
      -v|--verbose)
        VERBOSE=true; shift ;;
      -*)
        error "Unknown option: $1"
        show_usage; exit 1 ;;
      *)
        error "Unexpected positional argument: $1"
        show_usage; exit 1 ;;
    esac
  done
}

# ============================================================================
# Interactive Mode
# ============================================================================

prompt_for_inputs() {
  echo ""
  echo "GitLab Runner Registration"
  echo "=========================="

  if [[ -z "$GITLAB_URL" ]] || [[ "$GITLAB_URL" == "https://gitlab.example.com" ]]; then
    read -r -p "GitLab URL (https://gitlab.example.com): " url_input
    GITLAB_URL="${url_input:-https://gitlab.example.com}"
  fi

  if [[ -z "$RUNNER_TOKEN" ]]; then
    read -r -p "Runner authentication token (glrt-xxx): " token_input
    RUNNER_TOKEN="$token_input"
  fi

  if [[ -z "$RUNNER_NAME" ]]; then
    read -r -p "Runner name/hostname (e.g., runner-1): " name_input
    RUNNER_NAME="$name_input"
  fi

  if [[ "$RUNNER_EXECUTOR" == "docker" ]]; then
    read -r -p "Docker image (default: alpine:latest): " img_input
    DOCKER_IMAGE="${img_input:-alpine:latest}"
  fi

  echo ""
  echo "Summary:"
  echo "  GitLab URL:       $GITLAB_URL"
  echo "  Runner Name:      $RUNNER_NAME"
  echo "  Token:            ${RUNNER_TOKEN:0:20}..."
  echo "  Executor:         $RUNNER_EXECUTOR"
  if [[ "$RUNNER_EXECUTOR" == "docker" ]]; then
    echo "  Docker Image:     $DOCKER_IMAGE"
  fi
  echo "  Deploy Method:    $DEPLOY_METHOD"

  if [[ "$YES" == false ]]; then
    read -r -p "Proceed? (y/N): " -n 1 reply; echo
    if [[ ! "$reply" =~ ^[Yy]$ ]]; then
      info "Cancelled by user"
      exit 0
    fi
  fi
}

# ============================================================================
# Main
# ============================================================================

main() {
  parse_arguments "$@"

  info "GitLab runner registration script started"

  # Collect inputs if missing
  if [[ -z "$RUNNER_NAME" ]] || [[ -z "$RUNNER_TOKEN" ]]; then
    prompt_for_inputs
  fi

  # Validate inputs
  if ! validate_url "$GITLAB_URL"; then
    error "GitLab URL validation failed"
    exit 1
  fi

  if ! validate_token "$RUNNER_TOKEN"; then
    error "Runner token validation failed"
    exit 1
  fi

  if ! validate_runner_name "$RUNNER_NAME"; then
    error "Runner name validation failed"
    exit 1
  fi

  # Check prerequisites
  if ! check_prerequisites; then
    error "Prerequisite checks failed"
    exit 1
  fi

  # Register runner based on deployment method
  if [[ "$DEPLOY_METHOD" == "local" ]]; then
    if register_runner_local "$RUNNER_NAME" "$RUNNER_TOKEN" "$GITLAB_URL" "$RUNNER_EXECUTOR"; then
      success "Runner registered successfully"
      info "Completed successfully"
      exit 0
    else
      error "Runner registration failed"
      exit 1
    fi
  elif [[ "$DEPLOY_METHOD" == "docker" ]]; then
    if register_runner_docker "$RUNNER_NAME" "$RUNNER_TOKEN" "$GITLAB_URL" "$RUNNER_EXECUTOR"; then
      success "Docker runner configured"
      info "Completed successfully"
      exit 0
    else
      error "Docker runner setup failed"
      exit 1
    fi
  else
    error "Unknown deploy method: $DEPLOY_METHOD"
    exit 1
  fi
}

# ============================================================================
# Script Entry Point
# ============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
