#!/bin/bash
set -euo pipefail

# -----------------------------
# Centralized Deployment Reloader
# -----------------------------
# Watches a specific Deployment's ConfigMaps and Secrets, triggers rollout on changes.
# -----------------------------

DEPLOYMENT_NAME=${DEPLOYMENT_NAME:?Please set DEPLOYMENT_NAME}
NAMESPACE=${NAMESPACE:-default}
LABEL_SELECTOR=${LABEL_SELECTOR:?Please set LABEL_SELECTOR (app=<deployment-label>)}
CHECK_INTERVAL=${CHECK_INTERVAL:-10}  # seconds

declare -A LAST_CHECKSUMS

compute_checksum() {
  local TYPE=$1
  local NAME=$2
  kubectl get "$TYPE" "$NAME" -n "$NAMESPACE" -o yaml | sha256sum | awk '{print $1}'
}

patch_deployment() {
  local ANNOTATIONS=$1
  kubectl patch deployment "$DEPLOYMENT_NAME" -n "$NAMESPACE" \
    -p "{\"spec\":{\"template\":{\"metadata\":{\"annotations\":{${ANNOTATIONS}}}}}}"
}

echo "Starting centralized auto-reloader for Deployment '$DEPLOYMENT_NAME'..."

while true; do
  ANNOTATIONS=""
  CHANGED=false

  # Get all pod specs for the Deployment (to discover volumes)
  PODS=$(kubectl get pods -n "$NAMESPACE" -l "$LABEL_SELECTOR" -o jsonpath='{.items[*].metadata.name}')

  CONFIGMAPS=()
  SECRETS=()

  for POD in $PODS; do
    CM_NAMES=$(kubectl get pod "$POD" -n "$NAMESPACE" -o jsonpath='{.spec.volumes[*].configMap.name}' | tr ' ' '\n' | sort -u)
    SEC_NAMES=$(kubectl get pod "$POD" -n "$NAMESPACE" -o jsonpath='{.spec.volumes[*].secret.secretName}' | tr ' ' '\n' | sort -u)
    for CM in $CM_NAMES; do [ -n "$CM" ] && CONFIGMAPS+=("$CM"); done
    for SEC in $SEC_NAMES; do [ -n "$SEC" ] && SECRETS+=("$SEC"); done
  done

  # Deduplicate arrays
  CONFIGMAPS=($(echo "${CONFIGMAPS[@]}" | tr ' ' '\n' | sort -u))
  SECRETS=($(echo "${SECRETS[@]}" | tr ' ' '\n' | sort -u))

  # Compute checksums for ConfigMaps
  for CM in "${CONFIGMAPS[@]}"; do
    CHECKSUM=$(compute_checksum configmap "$CM")
    if [[ "${LAST_CHECKSUMS["configmap-$CM"]}" != "$CHECKSUM" ]]; then
      echo "ConfigMap $CM changed."
      LAST_CHECKSUMS["configmap-$CM"]=$CHECKSUM
      CHANGED=true
    fi
    ANNOTATIONS="${ANNOTATIONS}\"configmap-$CM-checksum\":\"$CHECKSUM\","
  done

  # Compute checksums for Secrets
  for SEC in "${SECRETS[@]}"; do
    CHECKSUM=$(compute_checksum secret "$SEC")
    if [[ "${LAST_CHECKSUMS["secret-$SEC"]}" != "$CHECKSUM" ]]; then
      echo "Secret $SEC changed."
      LAST_CHECKSUMS["secret-$SEC"]=$CHECKSUM
      CHANGED=true
    fi
    ANNOTATIONS="${ANNOTATIONS}\"secret-$SEC-checksum\":\"$CHECKSUM\","
  done

  ANNOTATIONS=${ANNOTATIONS%,}

  if [ "$CHANGED" = true ]; then
    echo "Patching Deployment due to detected changes..."
    patch_deployment "$ANNOTATIONS"
    echo "Deployment patched. Rolling update triggered."
  fi

  sleep "$CHECK_INTERVAL"
done
