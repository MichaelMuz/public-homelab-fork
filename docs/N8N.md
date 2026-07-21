# n8n

## State ownership

PostgreSQL, provided by the CloudNativePG cluster, owns n8n's durable application
state: workflows, credentials, users, executions, binary execution data, and the
record of installed community packages. The encryption key is the exception: it
is not stored in the database, it comes from the sealed secret, so the database
alone cannot decrypt stored credentials. Supplying it explicitly is deliberate:
left unset, n8n generates a key on first boot and stashes it in its user folder,
tying credential recovery to the PVC's survival. From the sealed secret it lives
in git like everything else.

In n8n 2.29.10, the default binary-data mode is `filesystem`. This deployment
explicitly sets `N8N_DEFAULT_BINARY_DATA_MODE=database`, so execution binary data
is stored in PostgreSQL instead of relying on the pod filesystem.

## User data and community packages

`N8N_USER_FOLDER=/data` gives n8n a persistent, writable user directory. n8n
writes user state under `/data/.n8n`, generated frontend cache under the sibling
`/data/.cache`, and installed community-package code under the same tree, so all
of it survives pod replacement. npm's cache is kept on `/tmp` because transient
downloads don't belong on the durable volume.

Community packages are intentionally enabled and UI-managed. This is an
exploration policy: packages can be tried, upgraded, and removed in the UI
without changing the Deployment. We can always switch to env-managed packages
(`N8N_COMMUNITY_PACKAGES`) later, but we don't yet know how we'll use packages,
so we keep it easy to iterate.

## Storage and rollout policy

The `/data` PVC's scope is n8n's local user directory and installed
community-package code; PostgreSQL remains the owner of application state.

The Deployment stays at one replica with the `Recreate` strategy. This both
fits the RWO attachment model and prevents two main n8n processes from briefly
running schedulers and triggers concurrently during a rollout.
