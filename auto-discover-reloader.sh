#!/bin/bash
set -euo pipefail

# -----------------------------
# Auto-Discover Multi-Deployment Reloader
# -----------------------------
# Automatically discovers all Deployments in the namespace and reloads them on changes.
# -----------------------------

NAMESPACE=${NAMESPACE:-default}
CHECK_INTERVAL=${CHECK_INTERVAL:-10}  # seconds

declare -A LAST_CHECKSUMS

compute_checksum() {
  local TYPE=$1
  local NAME=$2
  kubectl get "$TYPE" "$NAME" -n "$NAMESPACE" -o yaml | sha256sum | awk '{print $1}'
}

patch_deployment() {
  local DEPLOYMENT=$1
  local ANNOTATIONS=$2
  kubectl patch deployment "$DEPLOYMENT" -n "$NAMESPACE" \
    -p "{\"spec\":{\"template\":{\"metadata\":{\"annotations\":{${ANNOTATIONS}}}}}}"
}

echo "Starting auto-discover centralized reloader in namespace '$NAMESPACE'..."

while true; do
  # Get all deployments in the namespace
  DEPLOYMENTS=$(kubectl get deployments -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}')

  for DEP in $DEPLOYMENTS; do
    # Get label selector for pods of this deployment
    LABEL_SELECTOR=$(kubectl get deployment "$DEP" -n "$NAMESPACE" -o jsonpath='{.spec.selector.matchLabels}' | \
                     jq -r 'to_entries|map("\(.key)=\(.value)")|join(",")')
    ANNOTATIONS=""
    CHANGED=false

    PODS=$(kubectl get pods -n "$NAMESPACE" -l "$LABEL_SELECTOR" -o jsonpath='{.items[*].metadata.name}')

    CONFIGMAPS=()
    SECRETS=()

    for POD in $PODS; do
      CM_NAMES=$(kubectl get pod "$POD" -n "$NAMESPACE" -o jsonpath='{.spec.volumes[*].configMap.name}' | tr ' ' '\n' | sort -u)
      SEC_NAMES=$(kubectl get pod "$POD" -n "$NAMESPACE" -o jsonpath='{.spec.volumes[*].secret.secretName}' | tr ' ' '\n' | sort -u)
      for CM in $CM_NAMES; do [ -n "$CM" ] && CONFIGMAPS+=("$CM"); done
      for SEC in $SEC_NAMES; do [ -n "$SEC" ] && SECRETS+=("$SEC"); done
    done

    CONFIGMAPS=($(echo "${CONFIGMAPS[@]}" | tr ' ' '\n' | sort -u))
    SECRETS=($(echo "${SECRETS[@]}" | tr ' ' '\n' | sort -u))

    for CM in "${CONFIGMAPS[@]}"; do
      CHECKSUM=$(compute_checksum configmap "$CM")
      if [[ "${LAST_CHECKSUMS["$DEP-configmap-$CM"]}" != "$CHECKSUM" ]]; then
        echo "[$DEP] ConfigMap $CM changed."
        LAST_CHECKSUMS["$DEP-configmap-$CM"]=$CHECKSUM
        CHANGED=true
      fi
      ANNOTATIONS="${ANNOTATIONS}\"configmap-$CM-checksum\":\"$CHECKSUM\","
    done

    for SEC in "${SECRETS[@]}"; do
      CHECKSUM=$(compute_checksum secret "$SEC")
      if [[ "${LAST_CHECKSUMS["$DEP-secret-$SEC"]}" != "$CHECKSUM" ]]; then
        echo "[$DEP] Secret $SEC changed."
        LAST_CHECKSUMS["$DEP-secret-$SEC"]=$CHECKSUM
        CHANGED=true
      fi
      ANNOTATIONS="${ANNOTATIONS}\"secret-$SEC-checksum\":\"$CHECKSUM\","
    done

    ANNOTATIONS=${ANNOTATIONS%,}

    if [ "$CHANGED" = true ]; then
      echo "[$DEP] Patching Deployment due to detected changes..."
      patch_deployment "$DEP" "$ANNOTATIONS"
      echo "[$DEP] Deployment patched. Rolling update triggered."
    fi
  done

  sleep "$CHECK_INTERVAL"
done
