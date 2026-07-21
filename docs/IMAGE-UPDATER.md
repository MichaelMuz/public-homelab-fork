# Image updater

## What happens when you push an image

You push a new `latest` image to ghcr.io. The image updater polls the registry every ~2 minutes and notices the digest behind `latest` changed. It writes the new digest as a helm parameter on the ArgoCD Application object in etcd. ArgoCD re-renders the helm chart with that parameter, the rendered manifest now has the new digest, ArgoCD sees a diff and syncs, Kubernetes rolls out new pods.

## How it's wired up

The `continuousDelivery` key in `app-of-apps/values.yaml` is where you declare which images to track. The app-of-apps has two templates that read from it:

1. **`image-updater.yaml`** generates the ImageUpdater CRD. This tells the image updater which images to poll in the registry and, via `manifestTargets`, which helm param keys to write to (e.g. `backend.image.tag`). Without `manifestTargets`, multiple images collide on the same default key and overwrite each other.

2. **`app-of-apps.yaml`** generates the ArgoCD Application as usual. It does NOT set helm params — that's important (see gotcha below).

On the app side, deployment templates read from `{{ .Values.backend.image.tag }}` etc. The app's own `values.yaml` provides defaults (`tag: latest`) so the chart renders before the image updater has ever run. Once the image updater writes a digest to `backend.image.tag` on the Application object, that overrides the default — Helm merges `values.yaml` with `--set` params and params always win.

So the chain is: you push to ghcr → image updater detects new digest → writes `backend.image.tag: latest@sha256:abc` as a param on the Application → ArgoCD renders the chart using that param instead of the `latest` default → manifest changes → sync → new pods.

## Gotcha: don't set default params in app-of-apps

If the app-of-apps template bakes helm params into the Application spec, selfHeal will fight the image updater. The app-of-apps constantly reconciles the Application back to what it rendered (`tag: latest`), reverting the image updater's digest overrides every time. Keep defaults in the app's own `values.yaml` — the app-of-apps doesn't know about that file, so selfHeal leaves the runtime params alone.

## Why image names appear in two places

`continuousDelivery` in app-of-apps and `values.yaml` in the app both list the same images. Different Helm charts can't read each other's values — one tells the updater what to watch, the other gives Helm defaults. Same data, different consumers that can't share.
