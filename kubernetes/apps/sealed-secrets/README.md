# Sealed Secrets

This directory contains the Helm chart configuration for sealed-secrets controller.

## Sealing Secrets

To encrypt secrets for this homelab, use the following command:

### Example Usage

```bash
# Create a secret (don't apply it!)
kubectl create secret generic porkbun-api-secret \
  --from-literal=api-key=pk1_your-actual-api-key \
  --from-literal=secret-key=sk1_your-actual-secret-key \
  --namespace=traefik-system \
  --dry-run=client -o yaml > porkbun-secret.yaml

# Seal the secret
kubeseal --controller-name sealed-secrets --controller-namespace sealed-secrets \
  -f porkbun-secret.yaml -o yaml > porkbun-sealedsecret.yaml

# Clean up the unencrypted file
rm porkbun-secret.yaml

# Add the sealed secret to your app's templates directory
mv porkbun-sealedsecret.yaml ../traefik/templates/
```

## Notes

- Secrets are sealed with `strict` scope by default (namespace and name must match exactly)
- The sealed secret can safely be committed to git
- Only the controller in this cluster can decrypt the sealed secrets
