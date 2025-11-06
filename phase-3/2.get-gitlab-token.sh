#!/usr/bin/env bash
#
# GitLab Personal Access Token Generator
# Generate admin tokens for automation using gitlab-rails runner
#
# Usage: ./get_gitlab_token.sh [options]
#

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${LOG_FILE:-/var/log/gitlab_token_generator.log}"
GITLAB_CONTAINER="${GITLAB_CONTAINER:-gitlab}"
DRY_RUN=false
VERBOSE=false
YES=false

# Token defaults
TOKEN_USERNAME="root"
TOKEN_NAME="automation-token"
TOKEN_SCOPES="api,create_runner"
TOKEN_EXPIRY="365"
OUTPUT_FILE=""

# ============================================================================
# Logging
# ============================================================================

if ! { mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null && touch "$LOG_FILE" 2>/dev/null; }; then
  LOG_FILE="$SCRIPT_DIR/gitlab_token_generator.log"
fi

_log() {
  local level="$1"; shift
  local message="$*"
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
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
# Utility Functions
# ============================================================================

# Check if user exists in GitLab
user_exists() {
  local username="$1"
  local check_result
  
  check_result=$(docker exec "${GITLAB_CONTAINER}" gitlab-rails runner -e production \
    "puts User.find_by(username: '$username').nil? ? 'false' : 'true'" 2>/dev/null || echo "error")
  
  echo "$check_result"
}

# ============================================================================
# Prerequisite Checks
# ============================================================================

check_prerequisites() {
  if ! command -v docker &>/dev/null; then
    error "Docker is not installed"
    return 1
  fi

  if ! docker ps --format "{{.Names}}" | grep -q "^${GITLAB_CONTAINER}$"; then
    error "GitLab container '${GITLAB_CONTAINER}' is not running"
    return 1
  fi

  if ! command -v openssl &>/dev/null; then
    error "openssl is not installed"
    return 1
  fi

  info "All prerequisites met"
  return 0
}

# ============================================================================
# Token Generation
# ============================================================================

generate_gitlab_token() {
  local username="$1"
  local token_name="$2"
  local scopes="$3"
  local expiry_days="$4"

  info "Generating GitLab personal access token for user: $username"

  # Check if user exists
  local user_check
  user_check=$(user_exists "$username")
  
  if [[ "$user_check" != "true" ]]; then
    error "User '$username' does not exist in GitLab"
    return 1
  fi

  info "User '$username' found"

  if [[ "$DRY_RUN" == true ]]; then
    info "(Dry run) Would create token:"
    info "  Username: $username"
    info "  Token Name: $token_name"
    info "  Scopes: $scopes"
    info "  Expiry: $expiry_days days"
    return 0
  fi

  # Convert scopes to Ruby array format
  local ruby_scopes
  ruby_scopes=$(scopes_to_ruby_array "$scopes")

  # Build Ruby script with proper JSON payload (avoids quoting issues)
  local ruby_script
  ruby_script=$(cat <<'RUBY'
require 'json'
begin
  data = JSON.parse(STDIN.read)
  
  user = User.find_by(username: data['username'])
  unless user
    puts "Error: User not found"
    exit 1
  end
  
  # Create token
  token = user.personal_access_tokens.create(
    scopes: data['scopes'],
    name: data['token_name'],
    expires_at: data['expiry_days'].days.from_now
  )
  
  unless token.save
    puts "Error: Failed to save token"
    puts token.errors.full_messages.join("\n")
    exit 1
  end
  
  puts "TOKEN_CREATED"
  puts "Username: #{user.username}"
  puts "Token: #{token.token}"
  puts "Token ID: #{token.id}"
  puts "Name: #{token.name}"
  puts "Scopes: #{token.scopes.join(', ')}"
  if token.expires_at
    puts "Expires: #{token.expires_at.strftime('%Y-%m-%d')}"
  end
  
rescue => e
  puts "Error: #{e.message}"
  exit 1
end
RUBY
)

  # Build JSON payload with proper scopes array
  local scopes_array
  scopes_array=$(echo "$scopes" | jq -R 'split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(length > 0))')
  
  local payload
  payload=$(jq -nc \
    --arg username "$username" \
    --arg token_name "$token_name" \
    --argjson scopes "$scopes_array" \
    --arg expiry_days "$expiry_days" \
    '{username: $username, token_name: $token_name, scopes: $scopes, expiry_days: ($expiry_days | tonumber)}')

  info "Executing token generation command..."
  local output
  if ! output=$(printf '%s' "$payload" | docker exec -i "${GITLAB_CONTAINER}" \
        gitlab-rails runner -e production "$ruby_script" 2>&1); then
    error "Failed to generate token: $output"
    return 1
  fi

  if echo "$output" | grep -q "^TOKEN_CREATED"; then
    success "Personal access token generated successfully"
    
    # Extract token from output
    local token
    token=$(echo "$output" | grep "^Token:" | awk '{print $2}')
    
    if [[ -z "$token" ]]; then
      error "Failed to extract token from response"
      return 1
    fi

    # Save to file if requested
    if [[ -n "$OUTPUT_FILE" ]]; then
      mkdir -p "$(dirname "$OUTPUT_FILE")"
      printf '%s' "$token" > "$OUTPUT_FILE"
      chmod 600 "$OUTPUT_FILE"
      info "Token saved to: $OUTPUT_FILE"
    fi

    # Display token details
    echo ""
    echo "=========================================="
    echo "✓ Personal Access Token Generated"
    echo "=========================================="
    echo "$output" | tail -n +2 | sed 's/^/  /'
    echo ""
    echo "⚠ IMPORTANT NOTES:"
    echo "  1. Token is displayed ONLY ONCE"
    echo "  2. Copy and save it immediately"
    echo "  3. Store securely (secrets manager)"
    echo "  4. Do NOT commit to version control"
    echo ""
    echo "Usage with runner scripts:"
    echo "  export GITLAB_TOKEN='$token'"
    echo "  ./create_gitlab_runner.sh -d 'my-runner'"
    echo "=========================================="
    
    return 0
  else
    error "Token generation failed"
    echo "$output"
    return 1
  fi
}

# ============================================================================
# Argument Parsing
# ============================================================================

show_usage() {
  cat <<EOF
Usage: $0 [options]

Generate a personal access token for GitLab automation (admin/root user)

Options:
  -u, --username <n>          GitLab username (default: root)
  -n, --name <name>           Token name (default: automation-token)
  -s, --scopes <scopes>       Comma-separated scopes
                              (default: api,create_runner)
                              Available: api, read_user, write_repository, 
                              read_api, create_runner, manage_runner, etc.
  -e, --expiry <days>         Expiration in days (default: 365)
                              Set to 0 for no expiration (requires service account)
  -c, --container <name>      GitLab container name (default: gitlab)
  -o, --output-file <path>    Save token to file (e.g., /tmp/gitlab_token)
  --dry-run                   Show what would be done
  -y, --yes                   Skip confirmation
  -v, --verbose               Verbose output
  -h, --help                  Show this help message

Scopes:
  api                         Full API access (required for runners)
  create_runner               Create runners
  manage_runner               Manage runners
  read_api                    Read API
  read_user                   Read user info
  write_repository            Write to repositories
  sudo                        Admin operations

Examples:
  # Generate token for root user (interactive)
  $0

  # For runner creation (recommended)
  $0 -u root -s api,create_runner -n runner-automation

  # With custom expiry
  $0 -u root -e 30  # 30 days expiry

  # Save to file
  $0 -o /tmp/gitlab_token.txt

  # For admin operations
  $0 -s api,sudo

Environment Variables:
  GITLAB_CONTAINER    GitLab container name (default: gitlab)
  LOG_FILE            Log file location

EOF
}

parse_arguments() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        show_usage; exit 0 ;;
      -u|--username)
        TOKEN_USERNAME="$2"; shift 2 ;;
      -n|--name)
        TOKEN_NAME="$2"; shift 2 ;;
      -s|--scopes)
        TOKEN_SCOPES="$2"; shift 2 ;;
      -e|--expiry)
        TOKEN_EXPIRY="$2"; shift 2 ;;
      -c|--container)
        GITLAB_CONTAINER="$2"; shift 2 ;;
      -o|--output-file)
        OUTPUT_FILE="$2"; shift 2 ;;
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
  echo "GitLab Personal Access Token Generator"
  echo "======================================="
  echo ""

  read -r -p "GitLab username (default: root): " user_input
  TOKEN_USERNAME="${user_input:-root}"

  read -r -p "Token name (default: automation-token): " name_input
  TOKEN_NAME="${name_input:-automation-token}"

  read -r -p "Scopes (default: api,create_runner): " scopes_input
  TOKEN_SCOPES="${scopes_input:-api,create_runner}"

  read -r -p "Expiry in days (default: 365): " expiry_input
  TOKEN_EXPIRY="${expiry_input:-365}"

  read -r -p "Save token to file? (optional, press Enter to skip): " file_input
  OUTPUT_FILE="$file_input"

  # Show summary
  echo ""
  echo "Summary:"
  echo "  Username:    $TOKEN_USERNAME"
  echo "  Token Name:  $TOKEN_NAME"
  echo "  Scopes:      $TOKEN_SCOPES"
  echo "  Expiry:      $TOKEN_EXPIRY days"
  if [[ -n "$OUTPUT_FILE" ]]; then
    echo "  Save to:     $OUTPUT_FILE"
  fi

  if [[ "$YES" == false ]]; then
    read -r -p "Proceed? (y/N): " -n 1 reply; echo
    if [[ ! "$reply" =~ ^[Yy]$ ]]; then
      info "Cancelled"
      exit 0
    fi
  fi
}

# ============================================================================
# Main
# ============================================================================

main() {
  parse_arguments "$@"

  info "GitLab token generator started"

  # Prompt if needed
  if [[ $# -eq 0 ]]; then
    prompt_for_inputs
  fi

  # Check prerequisites
  if ! check_prerequisites; then
    error "Prerequisite checks failed"
    exit 1
  fi

  # Generate token
  if generate_gitlab_token "$TOKEN_USERNAME" "$TOKEN_NAME" "$TOKEN_SCOPES" "$TOKEN_EXPIRY"; then
    success "Token generation completed successfully"
    info "Completed successfully"
    exit 0
  else
    error "Token generation failed"
    exit 1
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
