#!/bin/bash

set -e

read -p "Secret name: " SECRET_NAME
read -p "Namespace: " NAMESPACE

echo "Enter key=value pairs (empty line to finish):"
LITERAL_ARGS=()
while true; do
    read -p "> " line
    if [ -z "$line" ]; then break; fi
    LITERAL_ARGS+=(--from-literal="$line")
done

TEMP_FILE=$(mktemp)
trap "rm -f $TEMP_FILE" EXIT

kubectl create secret generic "$SECRET_NAME" \
    --namespace="$NAMESPACE" \
    "${LITERAL_ARGS[@]}" \
    --dry-run=client -o yaml >"$TEMP_FILE"

kubeseal --controller-name sealed-secrets --controller-namespace sealed-secrets \
    -f "$TEMP_FILE" -o yaml >"${SECRET_NAME}-sealedsecret.yaml"

echo "✅ Created: ${SECRET_NAME}-sealedsecret.yaml"
