#!/bin/bash
set -euo pipefail

# -----------------------------
# Multi-Deployment Centralized Reloader
# -----------------------------
# Watches multiple Deployments' ConfigMaps and Secrets, triggers rollout on changes.
# -----------------------------

# List of Deployments to watch (format: deployment_name:label_selector)
# Example: "myapp1:app=myapp1 myapp2:app=myapp2"
DEPLOYMENTS=${DEPLOYMENTS:?Please set DEPLOYMENTS environment variable}

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

echo "Starting multi-deployment centralized reloader for Deployments: $DEPLOYMENTS"

while true; do
  for DEP in $DEPLOYMENTS; do
    NAME=$(echo "$DEP" | cut -d':' -f1)
    LABEL_SELECTOR=$(echo "$DEP" | cut -d':' -f2)

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
      if [[ "${LAST_CHECKSUMS["$NAME-configmap-$CM"]}" != "$CHECKSUM" ]]; then
        echo "[$NAME] ConfigMap $CM changed."
        LAST_CHECKSUMS["$NAME-configmap-$CM"]=$CHECKSUM
        CHANGED=true
      fi
      ANNOTATIONS="${ANNOTATIONS}\"configmap-$CM-checksum\":\"$CHECKSUM\","
    done

    for SEC in "${SECRETS[@]}"; do
      CHECKSUM=$(compute_checksum secret "$SEC")
      if [[ "${LAST_CHECKSUMS["$NAME-secret-$SEC"]}" != "$CHECKSUM" ]]; then
        echo "[$NAME] Secret $SEC changed."
        LAST_CHECKSUMS["$NAME-secret-$SEC"]=$CHECKSUM
        CHANGED=true
      fi
      ANNOTATIONS="${ANNOTATIONS}\"secret-$SEC-checksum\":\"$CHECKSUM\","
    done

    ANNOTATIONS=${ANNOTATIONS%,}

    if [ "$CHANGED" = true ]; then
      echo "[$NAME] Patching Deployment due to detected changes..."
      patch_deployment "$NAME" "$ANNOTATIONS"
      echo "[$NAME] Deployment patched. Rolling update triggered."
    fi
  done

  sleep "$CHECK_INTERVAL"
done
