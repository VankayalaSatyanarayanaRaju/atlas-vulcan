#!/bin/sh
# Jaanch — kubectl-based config validator
# Reads YAML check files from $CHECK_DIR, validates env vars via kubectl exec.
# Generic: works with any K8s service that has pods with env vars.

NAMESPACE="${NAMESPACE:-default}"
CHECK_DIR="${CHECK_DIR:-/checks}"

echo "=========================================="
echo "Jaanch Config Validator"
echo "=========================================="
echo "Namespace: $NAMESPACE"
echo ""

strip_cr() {
  printf '%s' "$1" | tr -d '\r'
}

# Pod name cache
POD_CACHE_DIR=$(mktemp -d)

resolve_pod() {
  LABEL="$1"
  CACHE_KEY=$(printf '%s' "$LABEL" | tr '/' '_' | tr '=' '_')
  CACHE_FILE="$POD_CACHE_DIR/$CACHE_KEY"

  if [ -f "$CACHE_FILE" ]; then
    cat "$CACHE_FILE"
    return
  fi

  # Get running pods excluding those that are terminating (deletionTimestamp set).
  POD=$(kubectl get pod -n "$NAMESPACE" -l "$LABEL" \
    --field-selector=status.phase=Running \
    -o json 2>/dev/null \
    | jq -r '[.items[] | select(.metadata.deletionTimestamp == null)] | first | .metadata.name // empty' 2>/dev/null || echo "")
  printf '%s' "$POD" > "$CACHE_FILE"
  printf '%s' "$POD"
}

# Batch env dump cache
ENV_CACHE_DIR=$(mktemp -d)

dump_pod_env() {
  POD="$1"
  CACHE_FILE="$ENV_CACHE_DIR/$POD"

  if [ -f "$CACHE_FILE" ]; then
    return 0
  fi

  kubectl exec "$POD" -n "$NAMESPACE" -- env 2>/dev/null \
    | tr -d '\r' > "$CACHE_FILE" || true
}

get_env_value() {
  POD="$1"
  KEY="$2"
  CACHE_FILE="$ENV_CACHE_DIR/$POD"

  if [ ! -f "$CACHE_FILE" ]; then
    echo ""
    return
  fi

  awk -F'=' -v k="$KEY" '$1 == k { sub(/^[^=]*=/, ""); print; found=1; exit } END { if (!found) print "" }' "$CACHE_FILE"
}

# Process check files
TOTAL_PASS=0
TOTAL_FAIL=0
TOTAL_CHECKS=0
FAILURES=""

for CHECK_FILE in "$CHECK_DIR"/*.yaml; do
  [ -f "$CHECK_FILE" ] || continue
  FILENAME=$(basename "$CHECK_FILE")
  SERVICE=$(echo "$FILENAME" | sed 's/\.yaml$//')

  echo "------------------------------------------"
  echo "Service: $SERVICE"
  echo "------------------------------------------"

  CURRENT_NAME=""
  CURRENT_KEY=""
  CURRENT_TYPE=""
  CURRENT_EXPECTED=""
  IN_CHECK=0

  process_check() {
    [ -z "$CURRENT_NAME" ] && return
    [ -z "$CURRENT_KEY" ] && return
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))

    LABEL="app=$SERVICE"
    POD=$(resolve_pod "$LABEL")
    if [ -z "$POD" ]; then
      echo "  FAIL: $CURRENT_NAME - no running pod found for $LABEL"
      FAILURES="${FAILURES}\n  [$SERVICE] $CURRENT_NAME - no pod found for $LABEL"
      TOTAL_FAIL=$((TOTAL_FAIL + 1))
      return
    fi

    dump_pod_env "$POD"
    VAL=$(get_env_value "$POD" "$CURRENT_KEY")

    case "$CURRENT_TYPE" in
      skip)
        echo "  SKIP: $CURRENT_NAME"
        TOTAL_PASS=$((TOTAL_PASS + 1))
        return
        ;;
      notEmpty|required)
        if [ -z "$VAL" ]; then
          echo "  FAIL: $CURRENT_NAME - empty or not set"
          FAILURES="${FAILURES}\n  [$SERVICE] $CURRENT_NAME - empty or not set"
          TOTAL_FAIL=$((TOTAL_FAIL + 1))
          return
        fi
        ;;
      exact)
        if [ -z "$VAL" ]; then
          echo "  FAIL: $CURRENT_NAME - key '${CURRENT_KEY}' not found"
          FAILURES="${FAILURES}\n  [$SERVICE] $CURRENT_NAME - key not found"
          TOTAL_FAIL=$((TOTAL_FAIL + 1))
          return
        fi
        if [ "$VAL" != "$CURRENT_EXPECTED" ]; then
          echo "  FAIL: $CURRENT_NAME = '$VAL' (expected: '$CURRENT_EXPECTED')"
          FAILURES="${FAILURES}\n  [$SERVICE] $CURRENT_NAME = '$VAL' (expected: '$CURRENT_EXPECTED')"
          TOTAL_FAIL=$((TOTAL_FAIL + 1))
          return
        fi
        ;;
      pattern)
        if [ -z "$VAL" ]; then
          echo "  FAIL: $CURRENT_NAME - key '${CURRENT_KEY}' not found"
          FAILURES="${FAILURES}\n  [$SERVICE] $CURRENT_NAME - key not found"
          TOTAL_FAIL=$((TOTAL_FAIL + 1))
          return
        fi
        if ! echo "$VAL" | grep -qE "$CURRENT_EXPECTED"; then
          echo "  FAIL: $CURRENT_NAME = '$VAL' (pattern: $CURRENT_EXPECTED)"
          FAILURES="${FAILURES}\n  [$SERVICE] $CURRENT_NAME = '$VAL' (pattern: $CURRENT_EXPECTED)"
          TOTAL_FAIL=$((TOTAL_FAIL + 1))
          return
        fi
        ;;
      enum)
        if [ -z "$VAL" ]; then
          echo "  FAIL: $CURRENT_NAME - key '${CURRENT_KEY}' not found"
          FAILURES="${FAILURES}\n  [$SERVICE] $CURRENT_NAME - key not found"
          TOTAL_FAIL=$((TOTAL_FAIL + 1))
          return
        fi
        MATCH=0
        OLD_IFS="$IFS"
        IFS=","
        for ALLOWED in $CURRENT_EXPECTED; do
          if [ "$VAL" = "$ALLOWED" ]; then MATCH=1; fi
        done
        IFS="$OLD_IFS"
        if [ $MATCH -eq 0 ]; then
          echo "  FAIL: $CURRENT_NAME = '$VAL' (allowed: $CURRENT_EXPECTED)"
          FAILURES="${FAILURES}\n  [$SERVICE] $CURRENT_NAME = '$VAL' (allowed: $CURRENT_EXPECTED)"
          TOTAL_FAIL=$((TOTAL_FAIL + 1))
          return
        fi
        ;;
      range)
        if [ -z "$VAL" ]; then
          echo "  FAIL: $CURRENT_NAME - key '${CURRENT_KEY}' not found"
          FAILURES="${FAILURES}\n  [$SERVICE] $CURRENT_NAME - key not found"
          TOTAL_FAIL=$((TOTAL_FAIL + 1))
          return
        fi
        MIN=$(echo "$CURRENT_EXPECTED" | cut -d'-' -f1)
        MAX=$(echo "$CURRENT_EXPECTED" | cut -d'-' -f2)
        NUM=$(echo "$VAL" | grep -oE '^[0-9]+$' || echo "")
        if [ -z "$NUM" ] || [ "$NUM" -lt "$MIN" ] || [ "$NUM" -gt "$MAX" ]; then
          echo "  FAIL: $CURRENT_NAME = '$VAL' (range: $MIN-$MAX)"
          FAILURES="${FAILURES}\n  [$SERVICE] $CURRENT_NAME = '$VAL' (range: $MIN-$MAX)"
          TOTAL_FAIL=$((TOTAL_FAIL + 1))
          return
        fi
        ;;
    esac

    echo "  PASS: $CURRENT_NAME"
    TOTAL_PASS=$((TOTAL_PASS + 1))
  }

  while IFS= read -r line || [ -n "$line" ]; do
    line=$(printf '%s' "$line" | tr -d '\r')
    trimmed=$(echo "$line" | sed 's/^[[:space:]]*//')

    if echo "$trimmed" | grep -q '^- name:'; then
      process_check
      CURRENT_NAME=$(echo "$trimmed" | sed 's/^- name:[[:space:]]*//')
      CURRENT_KEY=""
      CURRENT_TYPE="notEmpty"
      CURRENT_EXPECTED=""
      IN_CHECK=1
      continue
    fi

    [ $IN_CHECK -eq 0 ] && continue

    case "$trimmed" in
      key:*)      CURRENT_KEY=$(echo "$trimmed" | sed 's/^key:[[:space:]]*//') ;;
      type:*)     CURRENT_TYPE=$(echo "$trimmed" | sed 's/^type:[[:space:]]*//') ;;
      expected:*) CURRENT_EXPECTED=$(echo "$trimmed" | sed 's/^expected:[[:space:]]*//' | sed 's/^"//;s/"$//') ;;
    esac
  done < "$CHECK_FILE"

  process_check
  echo ""
done

if [ $TOTAL_FAIL -gt 0 ]; then
  echo ""
  echo "=========================================="
  echo "Failing Checks ($TOTAL_FAIL):"
  echo "=========================================="
  printf "$FAILURES\n"
  echo ""
fi

rm -rf "$POD_CACHE_DIR" "$ENV_CACHE_DIR"

echo "=========================================="
echo "Results: $TOTAL_PASS passed, $TOTAL_FAIL failed out of $TOTAL_CHECKS"
echo "=========================================="

if [ $TOTAL_FAIL -gt 0 ]; then
  echo "VALIDATION FAILED"
  exit 1
else
  echo "ALL CHECKS PASSED"
fi
