#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: Scripts/codex_usage.sh [--raw | --json]

Fetch Codex usage and reset-credit data using ~/.codex/auth.json.

Environment overrides:
  CODEX_AUTH_FILE             Auth file path (default: $CODEX_HOME/auth.json or ~/.codex/auth.json)
  CODEX_CHATGPT_BASE_URL      API base URL (default: https://chatgpt.com/backend-api)
EOF
}

raw=false
json=false
for argument in "$@"; do
    case "$argument" in
        --raw) raw=true ;;
        --json) json=true ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
done

if [[ "$raw" == true && "$json" == true ]]; then
    printf '%s\n' 'error: --raw and --json cannot be used together' >&2
    exit 2
fi

for command_name in curl jq; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        printf 'error: %s is required\n' "$command_name" >&2
        exit 1
    fi
done

codex_home="${CODEX_HOME:-${HOME}/.codex}"
auth_file="${CODEX_AUTH_FILE:-${codex_home}/auth.json}"
base_url="${CODEX_CHATGPT_BASE_URL:-https://chatgpt.com/backend-api}"
base_url="${base_url%/}"

if [[ ! -r "$auth_file" ]]; then
    printf 'error: cannot read Codex auth file: %s\n' "$auth_file" >&2
    exit 1
fi

if ! jq -e . "$auth_file" >/dev/null 2>&1; then
    printf 'error: invalid JSON in Codex auth file: %s\n' "$auth_file" >&2
    exit 1
fi

access_token="$(jq -er '.tokens.access_token // .tokens.accessToken // empty' "$auth_file")" || {
    printf 'error: no OAuth access token found in %s\n' "$auth_file" >&2
    exit 1
}
account_id="$(jq -r '.tokens.account_id // .tokens.accountId // empty' "$auth_file")"

common_headers=(
    -H "Authorization: Bearer ${access_token}"
    -H 'Accept: application/json'
    -H 'User-Agent: CodexBar'
)
if [[ -n "$account_id" ]]; then
    common_headers+=( -H "ChatGPT-Account-ID: ${account_id}" )
fi

fetch() {
    local endpoint="$1"
    curl --fail-with-body --silent --show-error --max-time 30 \
        "${common_headers[@]}" \
        "${base_url}${endpoint}"
}

usage_json="$(fetch /wham/usage)" || {
    printf 'error: Codex usage request failed\n' >&2
    exit 1
}

reset_credits_json=''
if reset_credits_json="$(curl --fail --silent --show-error --max-time 10 \
    "${common_headers[@]}" \
    -H 'OpenAI-Beta: codex-1' \
    -H 'originator: Codex Desktop' \
    "${base_url}/wham/rate-limit-reset-credits")"; then
    :
else
    reset_credits_json=''
fi

if [[ "$json" == true ]]; then
    jq -n \
        --argjson usage "$usage_json" \
        --argjson reset_credits "${reset_credits_json:-null}" \
        '{usage: $usage, rate_limit_reset_credits: $reset_credits}'
    exit 0
fi

if [[ "$raw" == true ]]; then
    printf '%s\n' '--- /wham/usage ---'
    jq . <<<"$usage_json"
    if [[ -n "$reset_credits_json" ]]; then
        printf '%s\n' '--- /wham/rate-limit-reset-credits ---'
        jq . <<<"$reset_credits_json"
    fi
    exit 0
fi

printf '%s\n' 'Codex usage'
jq -r '
    def first($paths): . as $root
        | reduce $paths[] as $path (null; . // ($root | (try getpath($path) catch null)));
    def as_number:
        if . == null then null
        elif (type) == "number" then .
        elif (type) == "string" then (tonumber? )
        else null
        end;
    def whole($value):
        ($value | as_number) as $number
        | if $number == null then null else ($number | round | tostring) end;
    def formatted_date($value):
        if $value == null or $value == "" then null
        elif ($value | type) == "number" then ($value | strftime("%Y-%m-%d %H:%M:%S UTC"))
        elif ($value | type) == "string" then
            (($value | (tonumber? // null)) as $epoch
             | if $epoch == null then $value else ($epoch | strftime("%Y-%m-%d %H:%M:%S UTC")) end)
        else null
        end;
    def line($label; $value):
        if $value == null or $value == "" then null else ($label + ": " + ($value | tostring)) end;
    def pick($objects; $keys):
        reduce $objects[] as $object (null;
            . // (reduce $keys[] as $key (null; . // ($object[$key] // null)))
        );
    def remaining($paths): first($paths) as $used
        | if ($used | type) == "number" then (100 - $used) else null end;
    . as $response
    | (first([["individual_limit"], ["individualLimit"], ["rate_limit", "individual_limit"], ["rate_limit", "individualLimit"]]) // {}) as $standard
    | (first([["spend_control", "individual_limit"], ["spend_control"]]) // {}) as $spend
    | [$standard, $spend] as $limits
    | (pick($limits; ["limit", "monthly_limit"]) | as_number) as $monthlyLimit
    | (pick($limits; ["used", "used_credits", "credits_used"]) | as_number) as $monthlyUsed
    | (pick($limits; ["remaining", "remaining_credits"]) | as_number) as $reportedMonthlyRemaining
    | (pick($limits; ["remaining_percent", "remainingPercent"]) | as_number) as $reportedMonthlyRemainingPercent
    | {
        plan: first([["plan_type"], ["planType"]]),
        credits_balance: first([["credits", "balance"], ["credits", "balanceUsd"], ["credits_balance"]]),
        session_remaining_percent: remaining([["rate_limit", "primary_window", "used_percent"]]),
        session_reset: first([["rate_limit", "primary_window", "reset_at"], ["rate_limit", "primary_window", "resetAt"]]),
        weekly_remaining_percent: remaining([["rate_limit", "secondary_window", "used_percent"]]),
        weekly_reset: first([["rate_limit", "secondary_window", "reset_at"], ["rate_limit", "secondary_window", "resetAt"]]),
        monthly_limit: $monthlyLimit,
        monthly_used: $monthlyUsed,
        monthly_remaining: ($reportedMonthlyRemaining // (if $monthlyLimit != null and $monthlyUsed != null then $monthlyLimit - $monthlyUsed else null end)),
        monthly_remaining_percent: ($reportedMonthlyRemainingPercent // (if $monthlyLimit != null and $monthlyLimit > 0 and $monthlyUsed != null then 100 - ($monthlyUsed / $monthlyLimit * 100) else null end)),
        monthly_reset: pick($limits; ["resets_at", "reset_at", "resetsAt", "resetAt"])
    }
    | [
        line("Plan"; .plan),
        line("Credits balance"; whole(.credits_balance)),
        line("Session limit remaining"; whole(.session_remaining_percent)),
        line("Session reset"; formatted_date(.session_reset)),
        line("Weekly limit remaining"; whole(.weekly_remaining_percent)),
        line("Weekly reset"; formatted_date(.weekly_reset)),
        line("Monthly/spend limit"; whole(.monthly_limit)),
        line("Monthly/spend used"; whole(.monthly_used)),
        line("Monthly/spend remaining"; whole(.monthly_remaining)),
        line("Monthly/spend remaining %"; whole(.monthly_remaining_percent)),
        line("Monthly/spend reset"; formatted_date(.monthly_reset))
      ]
    | map(select(. != null))[]
' <<<"$usage_json"

if [[ -n "$reset_credits_json" ]]; then
    reset_credit_lines="$(jq -r '
        def credits: (.credits // .data.credits // []);
        def formatted_date($value):
            if $value == null or $value == "" or $value == "no expiry" then null
            elif ($value | type) == "number" then ($value | strftime("%Y-%m-%d %H:%M:%S UTC"))
            elif ($value | type) == "string" then
                (($value | (tonumber? // null)) as $epoch
                 | if $epoch != null then ($epoch | strftime("%Y-%m-%d %H:%M:%S UTC"))
                   else (($value | (fromdateiso8601? // null)) as $date
                         | if $date == null then $value else ($date | strftime("%Y-%m-%d %H:%M:%S UTC")) end)
                   end)
            else null
            end;
        if (credits | length) == 0 then empty
        else
            "Available: " + ((credits | length) | tostring),
            (credits[]?
             | ((.expires_at // .expiresAt) | formatted_date(.)) as $expiry
             | if $expiry == null then empty else "Expires: " + $expiry end)
        end
    ' <<<"$reset_credits_json")"
    if [[ -n "$reset_credit_lines" ]]; then
        printf '%s\n' 'Limit reset credits'
        printf '%s\n' "$reset_credit_lines"
    fi
fi
