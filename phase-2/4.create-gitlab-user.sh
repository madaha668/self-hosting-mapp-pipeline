#!/usr/bin/env bash
#
# Enhanced GitLab user creation script (cleaned-up)
# Securely creates GitLab users with validation, sane logging, and robust escaping
#
# Usage: ./create_gitlab_user.sh [options]
# - Interactive mode prompts for missing fields (password hidden)
# - Or pass password via STDIN:  printf '%s\n' 'Passw0rd!' | ./create_gitlab_user.sh -u alice -e alice@example.com
#

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${LOG_FILE:-/var/log/gitlab_user_creation.log}"
GITLAB_CONTAINER="${GITLAB_CONTAINER:-gitlab}"
DRY_RUN=false
VERBOSE=false
YES=false

# User creation defaults
IS_ADMIN=false
SKIP_CONFIRMATION=false

NEW_USERNAME=""
NEW_EMAIL=""
NEW_PASSWORD=""

# ============================================================================
# Logging and Output
# ============================================================================

# Ensure we have a writable logfile (fallback to script dir)
if ! { mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null && touch "$LOG_FILE" 2>/dev/null; }; then
  LOG_FILE="$SCRIPT_DIR/gitlab_user_creation.log"
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

# GitLab typically allows letters, numbers, underscores, periods, and dashes.
# We normalize to lowercase and validate allowed chars (1–255).
normalize_username() {
  local in="$1"
  echo "$in" | tr '[:upper:]' '[:lower:]'
}

validate_username() {
  local username="$1"
  # Allow a-z, 0-9, dot, underscore, dash; cannot start with dash or underscore
  if [[ ! "$username" =~ ^[a-z0-9._-]{1,255}$ ]]; then
    error "Invalid username: must be 1-255 chars of [a-z0-9._-]"
    return 1
  fi
  if [[ "$username" =~ ^[-_] ]]; then
    error "Invalid username: cannot start with hyphen or underscore"
    return 1
  fi
  info "Username validated: $username"
  return 0
}

validate_email() {
  local email="$1"
  if [[ ! "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
    error "Invalid email format: $email"
    return 1
  fi
  info "Email validated: $email"
  return 0
}

validate_password() {
  local password="$1"
  local username="$2"
  if [[ ${#password} -lt 8 ]]; then
    error "Password must be at least 8 characters long"
    return 1
  fi
  if [[ "$password" == "$username" ]]; then
    error "Password cannot be the same as username"
    return 1
  fi
  info "Password validated (length only; not logged)"
  return 0
}

# ============================================================================
# Prerequisite Checks
# ============================================================================

check_prerequisites() {
  if ! command -v docker &>/dev/null; then
    error "Docker is not installed or not in PATH"
    return 1
  fi
  if ! command -v jq &>/dev/null; then
    error "jq is required (for safe JSON payloads). Please install jq."
    return 1
  fi
  if ! docker ps --format "{{.Names}}" | grep -q "^${GITLAB_CONTAINER}$"; then
    error "GitLab container '${GITLAB_CONTAINER}' is not running"
    return 1
  fi
  # Verify we can run a tiny Rails runner snippet
  if ! docker exec "${GITLAB_CONTAINER}" gitlab-rails runner -e production 'puts 1' &>/dev/null; then
    error "Cannot run 'gitlab-rails runner' inside container '${GITLAB_CONTAINER}'"
    return 1
  fi
  info "All prerequisites met"
  return 0
}

# ============================================================================
# User Creation (Ruby via stdin, JSON payload to avoid quoting issues)
# ============================================================================

create_gitlab_user() {
  local username="$1" email="$2" password="$3"
  local admin_val="$IS_ADMIN" skip_confirmation="$SKIP_CONFIRMATION"

  info "Creating GitLab user: $username (type: $([ "$IS_ADMIN" = true ] && echo Admin || echo Regular))"

  if [[ "$DRY_RUN" == true ]]; then
    info "(Dry run mode) Would create user '$username' <$email> admin=$admin_val skip_confirmation=$skip_confirmation"
    return 0
  fi

  # Build JSON payload
  local payload
  payload=$(jq -nc \
    --arg u "$username" \
    --arg e "$email" \
    --arg p "$password" \
    --argjson admin "$([[ "$admin_val" == true ]] && echo true || echo false)" \
    --argjson skip "$([[ "$skip_confirmation" == true ]] && echo true || echo false)" \
    '{username:$u, email:$e, password:$p, admin:$admin, skip:$skip}')

  # Ruby script (kept short; safe to pass as arg)
  local ruby_script
  ruby_script=$(cat <<'RUBY'
require 'json'
begin
  data = JSON.parse(STDIN.read)
  username = data["username"]
  email    = data["email"]
  password = data["password"]
  admin    = !!data["admin"]
  skip     = !!data["skip"]

  if User.find_by(username: username)
    puts "Error: Username '#{username}' already exists"; exit 1
  end
  if User.find_by(email: email)
    puts "Error: Email '#{email}' already exists"; exit 1
  end

  attrs = {
    username: username,
    email: email,
    name: username,
    password: password,
    password_confirmation: password,
    admin: admin
  }
  attrs[:confirmed_at] = Time.now if skip

  new_user = User.new(attrs)
  begin
    default_org = Organizations::Organization.default_organization
    new_user.assign_personal_namespace(default_org)
  rescue => e
    puts "Warning: Could not assign organization namespace (may not be needed): #{e.message}"
  end
  unless new_user.save
    puts "Failed to create user:"
    new_user.errors.full_messages.each { |m| puts "  - #{m}" }
    exit 1
  end

  puts "SUCCESS"
  puts "User ID: #{new_user.id}"
  puts "Username: #{new_user.username}"
  puts "Email: #{new_user.email}"
  puts "Admin: #{new_user.admin}"
  puts "Confirmed: #{new_user.confirmed?}"
rescue => e
  puts "Exception: #{e.class}: #{e.message}"
  exit 1
end
RUBY
)

  local output
  if ! output=$(printf '%s' "$payload" | docker exec -i "${GITLAB_CONTAINER}" \
        gitlab-rails runner -e production "$ruby_script" 2>&1); then
    error "Failed to create user: $output"
    return 1
  fi

  if echo "$output" | grep -qx "SUCCESS"; then
    success "User created successfully"
    info "User created: $username <$email>"
    echo "$output" | tail -n +2 | sed 's/^/  /'
    return 0
  else
    error "User creation failed: $output"
    return 1
  fi
}

# ============================================================================
# Argument Parsing
# ============================================================================

show_usage() {
  cat <<EOF
Usage: $0 [options]

Creates a new GitLab user (interactive or with arguments)

Options:
  -u, --username <name>         Username (prompted if not provided; normalized to lowercase)
  -e, --email <email>           Email address (prompted if not provided)
  -p, --password <password>     Password (WARNING: insecure; shows in ps/history)
                                Prefer passing via STDIN or interactive prompt.
  -a, --admin                   Create as admin user
  -s, --skip-confirmation       Skip email confirmation
  --container <name>            GitLab container name (default: gitlab)
  --dry-run                     Show what would be done, don't create user
  -y, --yes                     Non-interactive approval (skip confirmation if prompting)
  -v, --verbose                 Verbose output
  -h, --help                    Show this help message

Examples:
  # Interactive mode (secure)
  $0

  # All args (password via flag is discouraged)
  $0 -u john -e john@example.com -p 'SecurePass123!' -a

  # With STDIN password (secure; no echo)
  printf '%s\n' 'SecurePass123!' | $0 -u john -e john@example.com
EOF
}

parse_arguments() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        show_usage; exit 0 ;;
      -u|--username)
        NEW_USERNAME="$2"; shift 2 ;;
      -e|--email)
        NEW_EMAIL="$2"; shift 2 ;;
      -p|--password)
        NEW_PASSWORD="$2"; shift 2
        warn "Using -p/--password exposes secrets in process list and shell history" ;;
      -a|--admin)
        IS_ADMIN=true; shift ;;
      -s|--skip-confirmation)
        SKIP_CONFIRMATION=true; shift ;;
      --container)
        GITLAB_CONTAINER="$2"; shift 2 ;;
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
        # no positional args supported
        error "Unexpected positional argument: $1"
        show_usage; exit 1 ;;
    esac
  done
}

# ============================================================================
# Interactive / Non-interactive Inputs
# ============================================================================

read_password_from_stdin() {
  # If no password flag and stdin is not a TTY, read exactly one line
  if [[ -z "${NEW_PASSWORD:-}" && ! -t 0 ]]; then
    IFS= read -r NEW_PASSWORD || true
    # Trim trailing CR (Windows pipes)
    NEW_PASSWORD="${NEW_PASSWORD%$'\r'}"
  fi
}

prompt_for_credentials() {
  local username="${NEW_USERNAME:-}"
  local email="${NEW_EMAIL:-}"
  local password="${NEW_PASSWORD:-}"

  if [[ -z "$username" ]]; then
    read -r -p "Enter username: " username
  fi
  if [[ -z "$email" ]]; then
    read -r -p "Enter email: " email
  fi
  if [[ -z "$password" ]]; then
    read -rs -p "Enter password: " password; echo
  fi

  local user_type=$([ "$IS_ADMIN" = true ] && echo "Admin" || echo "Regular")
  echo ""
  echo "Summary:"
  echo "  Username:       $username"
  echo "  Email:          $email"
  echo "  User type:      $user_type"
  echo "  Email confirm:  $([ "$SKIP_CONFIRMATION" = true ] && echo "Skipped" || echo "Required")"

  if [[ "$YES" == false ]]; then
    read -r -p "Proceed? (y/N): " -n 1 reply; echo
    if [[ ! "$reply" =~ ^[Yy]$ ]]; then
      info "Cancelled by user"
      exit 0
    fi
  fi

  NEW_USERNAME="$username"
  NEW_EMAIL="$email"
  NEW_PASSWORD="$password"
}

# ============================================================================
# Main
# ============================================================================

main() {
  if [ $# -eq 0 ]; then
    show_usage
    exit 1
  fi 
  parse_arguments "$@"
  read_password_from_stdin

  info "GitLab user creation script started"

  if ! check_prerequisites; then
    error "Prerequisite checks failed"
    exit 1
  fi

  # Collect inputs (prompt if missing)
  if [[ -z "${NEW_USERNAME:-}" || -z "${NEW_EMAIL:-}" || -z "${NEW_PASSWORD:-}" ]]; then
    prompt_for_credentials
  fi

  # Normalize + validate
  NEW_USERNAME="$(normalize_username "$NEW_USERNAME")"
  if ! validate_username "$NEW_USERNAME"; then
    error "Username validation failed: $NEW_USERNAME"
    exit 1
  fi
  if ! validate_email "$NEW_EMAIL"; then
    error "Email validation failed: $NEW_EMAIL"
    exit 1
  fi
  if ! validate_password "$NEW_PASSWORD" "$NEW_USERNAME"; then
    error "Password validation failed"
    exit 1
  fi

  # Create user
  if create_gitlab_user "$NEW_USERNAME" "$NEW_EMAIL" "$NEW_PASSWORD"; then
    success "User creation completed successfully"
    info "Completed successfully: $NEW_USERNAME"
    exit 0
  else
    error "User creation failed"
    exit 1
  fi
}

# ============================================================================
# Script Entry Point
# ============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
