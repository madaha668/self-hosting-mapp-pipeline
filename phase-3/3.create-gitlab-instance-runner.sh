#!/usr/bin/env bash
#
# GitLab Instance-Level Runner Creation Script
# Creates instance runners using the modern runner creation workflow (GitLab 15.10+)
#
# Usage: ./create_gitlab_runner.sh [options]
#

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${LOG_FILE:-/var/log/gitlab_runner_creation.log}"
GITLAB_URL="${GITLAB_URL:-https://gitlab.example.com}"
GITLAB_TOKEN="${GITLAB_TOKEN:-}"
DRY_RUN=false
VERBOSE=false
YES=false

# Runner defaults
RUNNER_DESCRIPTION=""
RUNNER_TAGS=""
RUNNER_RUN_UNTAGGED=true
RUNNER_LOCKED=false
RUNNER_MAINTENANCE_NOTE=""

# Output file for storing token
TOKEN_OUTPUT_FILE=""

# ============================================================================
# Logging and Output
# ============================================================================

# Ensure we have a writable logfile (fallback to script dir)
if ! { mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null && touch "$LOG_FILE" 2>/dev/null; }; then
  LOG_FILE="$SCRIPT_DIR/gitlab_runner_creation.log"
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

validate_description() {
  local desc="$1"
  if [[ -z "$desc" ]]; then
    error "Runner description cannot be empty"
    return 1
  fi
  if [[ ${#desc} -gt 255 ]]; then
    error "Runner description must be 255 characters or less"
    return 1
  fi
  info "Runner description validated: $desc"
  return 0
}

validate_tags() {
  local tags="$1"
  # Tags can be empty, or comma-separated alphanumeric values
  if [[ -n "$tags" ]] && [[ ! "$tags" =~ ^[a-zA-Z0-9_,\ -]+$ ]]; then
    error "Invalid tags format: use alphanumeric, underscore, dash, comma"
    return 1
  fi
  info "Runner tags validated: ${tags:-none}"
  return 0
}

# ============================================================================
# Prerequisite Checks
# ============================================================================

check_prerequisites() {
  if ! command -v curl &>/dev/null; then
    error "curl is not installed or not in PATH"
    return 1
  fi
  if ! command -v jq &>/dev/null; then
    error "jq is required (for JSON processing). Please install jq."
    return 1
  fi

  # Validate GitLab URL is accessible
  info "Testing GitLab API connectivity..."
  local api_check
  if ! api_check=$(curl -s -o /dev/null -w "%{http_code}" \
        -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
        "$GITLAB_URL/api/v4/user"); then
    error "Cannot reach GitLab instance at $GITLAB_URL"
    return 1
  fi

  if [[ "$api_check" == "401" ]]; then
    error "Invalid GitLab token or insufficient permissions"
    return 1
  fi
  if [[ "$api_check" != "200" ]]; then
    error "GitLab API returned HTTP $api_check"
    return 1
  fi

  info "All prerequisites met"
  return 0
}

# ============================================================================
# Runner Creation (via REST API)
# ============================================================================

create_instance_runner() {
  local description="$1"
  local tags="$2"
  local run_untagged="$3"
  local locked="$4"
  local maintenance_note="$5"

  info "Creating GitLab instance-level runner: $description"

  if [[ "$DRY_RUN" == true ]]; then
    info "(Dry run mode) Would create runner with:"
    info "  Description: $description"
    info "  Tags: ${tags:-none}"
    info "  Run untagged: $run_untagged"
    info "  Locked: $locked"
    return 0
  fi

  # Build JSON payload
  local tag_list_json
  if [[ -z "$tags" ]]; then
    tag_list_json='[]'
  else
    # Convert comma-separated tags to JSON array
    tag_list_json=$(echo "$tags" | jq -Rs 'split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(length > 0))')
  fi

  local payload
  payload=$(jq -nc \
    --arg desc "$description" \
    --argjson tags "$tag_list_json" \
    --arg runner_type "instance_type" \
    --argjson run_untagged "$([[ "$run_untagged" == true ]] && echo true || echo false)" \
    --argjson locked "$([[ "$locked" == true ]] && echo true || echo false)" \
    --arg maint_note "${maintenance_note:-}" \
    '{
      runner_type: $runner_type,
      description: $desc,
      tag_list: $tags,
      run_untagged: $run_untagged,
      locked: $locked,
      maintenance_note: $maint_note
    }' | jq 'if .maintenance_note == "" then del(.maintenance_note) else . end')

  info "Sending API request to create runner..."
  local response
  if ! response=$(curl -s -X POST \
        -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        "$GITLAB_URL/api/v4/user/runners" 2>&1); then
    error "Failed to create runner: API request failed"
    return 1
  fi

  # Check if response contains an error
  if echo "$response" | jq -e '.error' &>/dev/null 2>&1; then
    local err_msg
    err_msg=$(echo "$response" | jq -r '.error // .message // "Unknown error"')
    error "API error: $err_msg"
    return 1
  fi

  # Extract runner token and ID
  local runner_token runner_id
  if ! runner_token=$(echo "$response" | jq -r '.token // empty' 2>/dev/null); then
    error "Failed to parse runner token from response"
    return 1
  fi
  if ! runner_id=$(echo "$response" | jq -r '.id // empty' 2>/dev/null); then
    error "Failed to parse runner ID from response"
    return 1
  fi

  if [[ -z "$runner_token" ]] || [[ "$runner_token" == "null" ]]; then
    error "No runner token returned from API"
    return 1
  fi

  success "Runner created successfully"
  info "Runner created: ID=$runner_id"

  # Save token to file if requested
  if [[ -n "$TOKEN_OUTPUT_FILE" ]]; then
    if ! { mkdir -p "$(dirname "$TOKEN_OUTPUT_FILE")" && touch "$TOKEN_OUTPUT_FILE" 2>/dev/null; }; then
      warn "Could not save token to $TOKEN_OUTPUT_FILE (permission denied)"
    else
      chmod 600 "$TOKEN_OUTPUT_FILE" 2>/dev/null || true
      printf '%s' "$runner_token" > "$TOKEN_OUTPUT_FILE" 2>/dev/null || true
      info "Runner token saved to: $TOKEN_OUTPUT_FILE"
    fi
  fi

  # Display token (only once, as it won't be shown again)
  echo ""
  echo "=========================================="
  echo "✓ Runner Created Successfully"
  echo "=========================================="
  echo "Runner ID:          $runner_id"
  echo "Description:        $description"
  echo "Tags:               ${tags:-none}"
  echo "Run Untagged:       $run_untagged"
  echo "Locked:             $locked"
  echo ""
  echo "Runner Token:       $runner_token"
  echo "Token Prefix:       glrt-"
  echo ""
  echo "⚠ IMPORTANT: Save the token above securely!"
  echo "The token will not be shown again."
  echo ""
  echo "Next steps:"
  echo "1. Store the token in your secrets management system"
  echo "2. Use the token to register runners:"
  echo ""
  echo "   gitlab-runner register --non-interactive \\"
  echo "     --url '$GITLAB_URL' \\"
  echo "     --token '$runner_token' \\"
  echo "     --executor docker \\"
  echo "     --docker-image alpine:latest"
  echo "=========================================="

  return 0
}

# ============================================================================
# Argument Parsing
# ============================================================================

show_usage() {
  cat <<EOF
Usage: $0 [options]

Creates a new GitLab instance-level runner using the modern runner creation workflow

Options:
  -u, --url <url>               GitLab instance URL (default: https://gitlab.example.com)
                                Can also use GITLAB_URL environment variable
  -t, --token <token>           GitLab personal access token with api+create_runner scopes
                                Can also use GITLAB_TOKEN environment variable
  -d, --description <desc>      Runner description (required, max 255 chars)
  -g, --tags <tags>             Comma-separated tags (e.g., "docker,linux,prod")
  -u, --run-untagged           Jobs tagged with any tag can be run by this runner (default: true)
  --no-run-untagged            Only jobs with matching tags can be run
  -l, --locked                  Lock runner to assigned projects only
  -m, --maintenance-note <note> Maintenance notes for the runner
  --dry-run                     Show what would be done, don't create runner
  -o, --output-file <path>      Save runner token to file (e.g., /tmp/runner_token)
  -y, --yes                     Skip confirmation prompt
  -v, --verbose                 Verbose output
  -h, --help                    Show this help message

Environment Variables:
  GITLAB_URL                    GitLab instance URL
  GITLAB_TOKEN                  GitLab personal access token

Required:
  - GITLAB_TOKEN or -t/--token must be provided
  - Description (-d/--description) is required
  - GITLAB_URL or -u/--url should be set

Examples:
  # Interactive (prompts for required fields)
  $0

  # Create production docker runner with token
  $0 -t 'glpat-xxxx' -d 'prod-docker-runner' -g docker,linux -u https://gitlab.example.com

  # Save token to file
  $0 -t 'glpat-xxxx' -d 'runner-1' -o /tmp/runner_token.txt

  # Locked runner for specific projects only
  $0 -t 'glpat-xxxx' -d 'private-runner' -l

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
        GITLAB_TOKEN="$2"; shift 2 ;;
      -d|--description)
        RUNNER_DESCRIPTION="$2"; shift 2 ;;
      -g|--tags)
        RUNNER_TAGS="$2"; shift 2 ;;
      --run-untagged)
        RUNNER_RUN_UNTAGGED=true; shift ;;
      --no-run-untagged)
        RUNNER_RUN_UNTAGGED=false; shift ;;
      -l|--locked)
        RUNNER_LOCKED=true; shift ;;
      -m|--maintenance-note)
        RUNNER_MAINTENANCE_NOTE="$2"; shift 2 ;;
      --dry-run)
        DRY_RUN=true; shift ;;
      -o|--output-file)
        TOKEN_OUTPUT_FILE="$2"; shift 2 ;;
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
  echo "GitLab Instance-Level Runner Creation"
  echo "======================================"

  # Prompt for GitLab URL if not set
  if [[ -z "$GITLAB_URL" ]] || [[ "$GITLAB_URL" == "https://gitlab.example.com" ]]; then
    read -r -p "GitLab URL (https://gitlab.example.com): " url_input
    GITLAB_URL="${url_input:-https://gitlab.example.com}"
  fi

  # Prompt for token if not set
  if [[ -z "$GITLAB_TOKEN" ]]; then
    read -rs -p "GitLab Personal Access Token (with api+create_runner scopes): " token_input
    echo
    GITLAB_TOKEN="$token_input"
  fi

  # Prompt for description if not set
  if [[ -z "$RUNNER_DESCRIPTION" ]]; then
    read -r -p "Runner description (e.g., 'prod-docker-runner'): " desc_input
    RUNNER_DESCRIPTION="$desc_input"
  fi

  # Prompt for tags if not set
  if [[ -z "$RUNNER_TAGS" ]]; then
    read -r -p "Tags (comma-separated, e.g., 'docker,linux' or press Enter): " tags_input
    RUNNER_TAGS="$tags_input"
  fi

  # Show summary
  echo ""
  echo "Summary:"
  echo "  GitLab URL:       $GITLAB_URL"
  echo "  Description:      $RUNNER_DESCRIPTION"
  echo "  Tags:             ${RUNNER_TAGS:-none}"
  echo "  Run Untagged:     $RUNNER_RUN_UNTAGGED"
  echo "  Locked:           $RUNNER_LOCKED"

  # Confirm
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

  info "GitLab runner creation script started"

  # Collect inputs if missing
  if [[ -z "$RUNNER_DESCRIPTION" ]] || [[ -z "$GITLAB_TOKEN" ]]; then
    prompt_for_inputs
  fi

  # Validate inputs
  if ! validate_url "$GITLAB_URL"; then
    error "GitLab URL validation failed"
    exit 1
  fi

  if ! validate_description "$RUNNER_DESCRIPTION"; then
    error "Runner description validation failed"
    exit 1
  fi

  if ! validate_tags "$RUNNER_TAGS"; then
    error "Tags validation failed"
    exit 1
  fi

  # Check prerequisites
  if ! check_prerequisites; then
    error "Prerequisite checks failed"
    exit 1
  fi

  # Create runner
  if create_instance_runner "$RUNNER_DESCRIPTION" "$RUNNER_TAGS" "$RUNNER_RUN_UNTAGGED" "$RUNNER_LOCKED" "$RUNNER_MAINTENANCE_NOTE"; then
    success "Instance-level runner created successfully"
    info "Completed successfully"
    exit 0
  else
    error "Runner creation failed"
    exit 1
  fi
}

# ============================================================================
# Script Entry Point
# ============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
