# Hermes agent

Running [Hermes Agent](https://hermes-agent.nousresearch.com) (Nous Research's open, model-agnostic
agentic assistant) as an always-on butler in the lab. What we want from it, how it actually works,
and what we chose. Merged to `main` and deployed via Argo (2026-07-03); running and healthy.

## What we want from it

An always-on agent, reachable remotely, that watches the lab and the wider world, does delegated and
scheduled work, and reports back. A living wish list (the hard part is thinking these up, so add as
they land):

- **Lab monitors** (cron to Telegram): Argo/dependency drift, failed CronJobs, node/Longhorn/cert
  health; propose version bumps as PRs.
- **Scouting**: self-host ideas, homelab hardware deals, curated news on my topics.
- **Digests**: inbox + LinkedIn summary; daily recap and tomorrow's plan.
- **Delegated dev**: "fix issue #123 on repo X" while I'm away, it works in-pod and opens a PR.

## How Hermes works (what we learned)

It's one agent with persistent state, reachable through several **surfaces (doors)** that all hit the
same brain:

- **Messaging gateway** (Telegram, etc.): the quick remote channel, long-polls outbound so no inbound
  is needed.
- **Web dashboard** (`:9119`): a full control panel, chat plus a `config.yaml` editor and
  key/skill/cron management. Essentially root-equivalent power over the agent, so it stays behind auth.
- **OpenAI-compatible API** (`:8642`): use the agent as a model backend for LibreChat/etc., and it's
  also how the dashboard reaches the gateway internally.
- **CLI / TUI**: a Claude-Code-shaped terminal agent. Model-agnostic is its only real edge over Claude
  Code, so for local coding we'd just use Claude Code; this surface is basically vestigial for us.

The **capabilities** are the same through any door: run shell (terminal), read/write files, web
search, drive a browser, memory, skills, MCP tools, and cron for autonomous/scheduled runs.

**Boot model (the s6 bit, and it frames the security).** The image is s6-overlay: `/init` starts as
**root**, `chown`s the data dir, then drops to the unprivileged `hermes` user (uid 10000) and runs
`hermes gateway run` under supervision. This is the image's own privilege-drop, a docker-host idiom: the
root phase exists to fix bind-mount ownership, which plain `docker run` can't do for you. In k8s we don't
need it — `fsGroup` chowns the volume, so we start the container directly as uid 10000 and skip the root
phase entirely (see Security). s6's supervision itself never needed root; only those one-time chores did.
Consequence of skipping the root phase: root-phase helpers fail loudly but harmlessly at boot. As of
v2026.7.7 that's the chown warnings plus `s6-applyuidgid: fatal: unable to set supplementary group list`
from `docker_config_migrate.py` (a docker-layout config migration that doesn't apply here); all services
start normally after them.

**Stateful.** Config, sessions, skills, memories, and `.env` all live under `/opt/data`. The image is
otherwise stateless (upgrade by swapping the tag), so `/opt/data` is the thing to persist and back up.

## What we built

We evaluated the `ultraworkers` community chart but it was stale (pinned a dead `0.8.0`
tag, predated the s6/dashboard image), so we read it as a reference and built our own, which we also
want free rein to tweak.

- **Surfaces enabled**: gateway (Telegram), dashboard, and API server; the two HTTP ones behind
  `eg-private`/`https-admin` as `hermes-dashboard` / `hermes-openai-api`.admin.michaelmuzafarov.dev.
- PVC RWO 30Gi (Longhorn thin-provisions, so the size is a cap not a cost; expandable online, never
  shrinkable) at `/opt/data` — which is `HERMES_HOME` in the image, holding all state (config, `.env`,
  sessions, skills, cron). `Recreate` strategy (avoids the RWO + RollingUpdate cross-node deadlock we hit
  before). A rollout serves 503 at the gateway for a couple of minutes while the new pod's listeners come
  up; it clears on its own. `fsGroupChangePolicy: OnRootMismatch` so only the first mount pays the
  recursive chown walk.
- **Snapshot safety net (2026-07-07).** Longhorn RecurringJob `hermes-snapshot` snapshots the PVC every
  6h, retain 28 (≈ a week), so a self-inflicted `/opt/data` wipe is revertable. In-cluster COW snapshots,
  not backups, which matches the threat model (agent nukes itself, not cluster loss). The job CR lives in
  the chart (`templates/recurringjob.yaml`) but in the `longhorn-system` namespace, the only one Longhorn
  reconciles; the volume opts in via PVC labels (`recurring-job.longhorn.io/source` + `/hermes-snapshot`),
  which Longhorn periodically copies down to its Volume CR. Gotcha that cost a debug round: the label
  prefix is hyphenated `recurring-job.longhorn.io/`; the unhyphenated form from older docs is silently
  ignored. Hermes monitors the job himself via his own cron (his RBAC already reads longhorn.io snapshots).
- Kata / KubeVirt kept in the back pocket (a `runtimeClassName` swap) if a job ever needs real Docker.

## Security

Framed by how it actually works. Two boundaries: the perimeter and the pod-as-sandbox. The uid used to
be an open question; it no longer is.

- **We run non-root (uid 10000) from a fresh start.** Our first instinct was baseline-with-root, on the
  theory that forcing `runAsNonRoot` would fight s6's root-init. Reading `docker/stage2-hook.sh` proved
  otherwise: it explicitly permits a uid-10000 start (the guard rejects only *arbitrary* non-root uids),
  its `chown` fails safe when non-root, and the UID remap only fires if `HERMES_UID` is set. The root
  phase exists solely to fix bind-mount ownership; `fsGroup: 10000` does that for us, so we start as uid
  10000 with a writable `/run` emptyDir (s6's scandir) and skip root entirely. Boot-verified 2026-07-03:
  guard passed, stage2 completed, gateway + dashboard supervised as uid 10000, one surprise (next bullet).
- **The one knob that fought back: `/run` ownership.** kubelet creates every emptyDir owned by
  `root:root` (`fsGroup` fixes only the group; k8s has no way to set a volume's owner *uid*), and
  non-root s6 preinit refuses a `/run` it doesn't own — on a multi-user host a writable-but-unowned
  `/run` would let another user tamper with the supervision tree, so it exits fatal. First boot
  crash-looped on exactly this. The fix is s6's own opt-out for the k8s case,
  `S6_YES_I_WANT_A_WORLD_WRITABLE_RUN_BECAUSE_KUBERNETES=1` (deliberately embarrassing to type so
  nobody sets it unread): preinit downgrades the fatal to a warning and creates its own uid-10000
  subdirs under `/run`. Sound in a pod because every process is uid 10000 — the "other user" the
  check defends against doesn't exist here.
- **We went straight to restricted + read-only rootfs (max-hardness first).** Rather than ratchet in
  stages, the first apply is maximally locked: `capabilities: drop [ALL]` + explicit `seccompProfile:
  RuntimeDefault` (→ restricted-compliant, namespace flipped to `enforce: restricted`) plus
  `readOnlyRootFilesystem: true`. Readonly needs `S6_READ_ONLY_ROOT=1` (s6 stages into `/run` not `/etc`)
  and emptyDirs at `/run`, `/tmp`, `/var/tmp`; the image already seals `/opt/hermes` read-only by design
  and keeps all writable state on `/opt/data`. The bet: if it boots we're done; if a knob breaks it the
  failure names which one, and each is a one-line revert. `drop [ALL]` gives up `NET_RAW` (agent `ping`
  won't work) — acceptable. `readOnlyRootFilesystem` is the likeliest to hit an unforeseen write path, so
  it's the first suspect if boot fails.
- **The real boundary is the perimeter.** Both HTTP surfaces are private (`eg-private` = LAN/Tailscale
  only) with mandatory auth (dashboard basic-auth, API key). That's the mitigation the June-2026 campaign
  victims lacked (internet-exposed Hermes dashboards/API servers driven into planting SSH-key backdoors).
  Telegram is the exception: it long-polls outbound, so `eg-private` doesn't cover it — its only gate is
  the user allowlist, which fails closed (no allowlist = all denied). We authorize ourselves post-boot via
  the pairing flow (`hermes pairing approve telegram <code>`), keeping our Telegram id out of git.
- **The pod is the sandbox.** The agent's shell runs in-container (`terminal` native backend), so with no
  inner container the pod's own securityContext is the whole sandbox. `allowPrivilegeEscalation: false`
  seals setuid re-escalation; `automountServiceAccountToken: false` + no RBAC means a leaked token is inert
  (superseded 2026-07-07 by roadmap item 8: the token is now mounted, scoped read-only).
- **Audit deltas (2026-07-03).** Added resource limits (`1/4Gi → 2/8Gi`) so an arbitrary-code agent can't
  OOM/starve a node. seccomp `RuntimeDefault` is already applied cluster-wide (`seccompDefault: true` on
  every node), so we don't set it. Egress is already covered by the `deny-egress-to-hosts` clusterwide
  policy (pods → Proxmox IPs blocked); each namespace's ingress default-deny blocks lateral movement. The
  one control k8s won't let us set per-pod is a PID limit (a fork-bomb guard) — node-level `podPidsLimit` only.
- **Why we didn't fork the image.** Stripping s6 for a single-process k8s-native image is feasible, but the
  dynamic per-profile gateways are spawned by the agent at runtime and need an in-pod supervisor (they
  can't be k8s containers without giving the agent API access we denied). Upstream is moving toward s6, not
  away. Running the stock image non-root via k8s primitives gets the restricted posture without a fork.

### Security wish list (not done)

- ~~Read-only against every source; the only write path is GitHub PRs from a separate,
  blast-radius-limited account, never the main identity.~~ Done 2026-07-06 via roadmap item 7
  (GitHub + GitLab PRs from the `hermes-muzafarov` bot accounts).
- ~~A read-only ServiceAccount, only if a monitor ever needs the k8s API.~~ Done 2026-07-07 via
  roadmap item 8.
- A per-pod PID limit, if Talos grows a way to set one without node-wide kubelet config.

## Decisions & open questions

- **Config: dashboard-owned, minimum-first (decided).** Hermes is stateful; `config.yaml` + `.env` live on
  `/opt/data` and the dashboard edits them live. We don't git-seed or env-inject config — we boot with just
  the sealed provider key, set the model once in the dashboard, and let config persist on the (backed-up)
  PVC, same as the *arr stack. The main model *name* isn't env-settable anyway (only the provider is, via
  `HERMES_INFERENCE_PROVIDER`); precedence is CLI > config.yaml > .env > defaults. We expected a fresh
  install to ship `model: ""` (non-functional until picked); in practice first boot detected the
  OpenRouter key and auto-selected **Anthropic Opus 4.6**, chat-functional immediately. Later we may hand
  config management to the agent itself (it can push to a git repo).
- **Identity is composed from prompt "slots".** The system prompt is built from `SOUL.md` (slot #1,
  primary identity — the one file we hand-author), then project-context files, then auto-injected memory.
  Memory is two agent-managed files under `memories/`: `MEMORY.md` (conversation memory, ~2200-char cap)
  and `USER.md` (user profile, ~1375-char cap); both self-populate, `USER.md` can be seeded but doesn't
  need to be. All identity files hot-load per session (no pod restart; start a fresh chat to pick up a
  change). The dashboard exposes a file browser over `/opt/data`, so `SOUL.md` and friends are editable
  in the UI, not just via `kubectl`. `SOUL.md` text worth keeping a copy of in notes/repo since it lives
  on the PVC (backed up), not in git.
- **Full autonomy: every approval gate off (deliberate).** `memory.write_approval`,
  `skills.write_approval`, and sessions write-approval are all off; `memory_enabled` +
  `user_profile_enabled` on. The agent reads/writes memory, creates skills, and acts without per-action
  prompts. This is sound *because* of the hardening: the pod is the sandbox, so blast radius is contained
  at the boundary rather than by babysitting each call. `skills.guard_agent_created` stays on (it warns on
  dangerous skill patterns rather than gating, so it costs no interactivity). The autonomy line to hold is
  not per-action prompts but *credential scope* — see the GitHub/RBAC roadmap items; a sandbox can't
  un-leak a token.
- **Perimeter re-confirmed (2026-07-03).** Dashboard reachable on LAN and over Tailscale, blocked on
  bare 4G — the intended three-way result, so `eg-private` is doing its job.
- **Provider**: OpenRouter (`OPENROUTER_API_KEY` sealed). Nous's own Hermes models are Llama finetunes
  I don't rate, so we wanted a non-Llama open model. The auto-selected Opus 4.6 was ruled out for
  always-on (Anthropic pricing, plus OpenRouter's cut on top).
- **Main model: GLM-5.2 (decided 2026-07-03, set in the dashboard).** Shortlisted four open Chinese
  models on OpenRouter (in/out per 1M, context):
  - **GLM-5.2** (Zhipu, MIT, 753B/40B MoE) — $0.93 / $3.00, 1M. Text only.
  - **DeepSeek V4 Pro** (1.6T/49B MoE) — $0.435 / $0.87, 1M, advertises 60-80% prompt-cache savings. Text only.
  - **Kimi K2.7-Code** (Moonshot, 1T/32B MoE) — $0.74 / $3.50, 262K. Only multimodal one (text+image).
  - **Qwen3-Coder** (480B/35B MoE) — $0.22 / $1.80* headline but *tiered (that rate only ≤128K input, jumps above); weakest agentic rep.

  Picked GLM because Hermes's real workload is agentic tool-calling and GLM is the only one with
  *independently verified* MCP/agentic numbers (MCP-Atlas ≈ Opus 4.8); the others' agentic claims were
  first-party (Kimi) or unproven (Qwen). For an unattended agent that runs shell / opens PRs, proven
  tool-calling beat saving a few dollars at homelab volume. DeepSeek V4 Pro is the fallback if the bill
  ever bites (cheapest output + caching). GLM being text-only isn't a real limit — `auxiliary.*` routes
  vision/web-extraction to a separate model, so a monitor that needs to read an image points
  `auxiliary.vision` elsewhere and leaves GLM as the brain.
- **Later: a monthly sub, not per-token.** If one model earns its keep, get that lab's own subscription
  (well past OpenRouter's ~$20/mo effective spend) rather than paying per token with OpenRouter's cut on
  top. Deferred until we know which model we actually like.
- **Later: mixture-of-agents (MoA) experiment.** Hermes has an MoA mode (its own config section). Meshing
  several of these into an ensemble is a fun experiment for once the base single-model system feels solid
  — but MoA only pays off after we know each model's solo behavior, and it multiplies tokens + failure
  modes, so it waits. Opus-as-director was considered and rejected: it reintroduces exactly the
  always-on Anthropic cost we left, on every turn.

## Renovate reviews

Hermes reviews every Renovate draft MR before marking it ready and handing it to the operator. Hermes does:

1. identify the update type and whether it touches cluster-critical components,
2. read upstream release notes for breaking changes,
3. run the relevant local checks, usually `helm lint`/`helm template` for app charts and
   `tofu validate` for OpenTofu changes,
4. comment a short risk and validation summary.

The operator remains the final merger. `Available upstream` changes in `docs/VERSIONS.md` are
informational reminders; Renovate never changes its `Current/live version` fields.

## Roadmap

1. ~~Base gateway + dashboard + API, hand-rolled.~~ Built, on branch.
2. ~~Security hardening: non-root + restricted + read-only rootfs, resources, audit vs the community
   chart.~~ Staged (2026-07-03).
3. ~~Merge (squash) → Argo deploys. First boot verifies the whole non-root + restricted + read-only-rootfs
   profile in one shot (loosen per whatever the logs flag); pick the model, pair Telegram.~~ Done
   2026-07-03: profile held with one fix (the `/run` ownership env var, see Security); dashboard login
   works (via `/login`, see What we built); Telegram paired with `hermes pairing approve telegram <code>`
   via `kubectl exec` (runtime state on the PVC, Telegram id stays out of git). Verified end to end: chat
   from both surfaces, tool use, in-pod terminal (agent correctly reports it's on k8s/Talos).
4. ~~Swap the auto-selected Opus 4.6 for a non-Llama open model in the dashboard.~~ Done 2026-07-03:
   **GLM-5.2** (see Provider).
5. ~~Write `SOUL.md` (persona: lab-butler operating context, act-don't-ask autonomy, Telegram-brief voice,
   the one credential boundary).~~ Done 2026-07-05. `SOUL.md` hand-written, brief and persona/rules-only
   (voice, autonomy boundary, trust, one writing bullet); biography deliberately kept out. The rest of the
   identity was seeded by the agent itself: we temporarily set the model to a frontier one (Fable), ran a
   get-to-know-you Q&A feeding it the backstory, and let it write its own `memories/USER.md` and
   `MEMORY.md` through its memory tool, so the files stay in the harness's own format and within caps.
   `USER.md` holds only the always-in-context slice (it hit 80% of its ~1375-char cap mid-interview);
   deeper background went to topic files under `/opt/data` with a pointer line in `USER.md`, read
   on demand rather than injected every session. The raw interview stays retrievable via session
   full-text search (`state.db`). Verified on a fresh Telegram session after switching back to
   GLM-5.2: memory injected at session start, pointer files followed, persona held.
6. ~~First read-only monitor on Hermes's internal cron, reporting to Telegram (set up once by asking it on
   Telegram; then it runs autonomously, no code).~~ Done, set up over Telegram as planned, no code.
7. ~~**PR write path via an isolated GitHub account.**~~ Done 2026-07-06, broader than planned: the
   homelab and all other private repos moved to GitLab for free branch protection first (see
   docs/history/GITLAB-MIGRATION.md), so the write path spans both platforms under one bot identity,
   `hermes-muzafarov` (its own email, SSH key and PAT per platform; the fine-grained-PAT-only lean gave
   way to full bot accounts once the GitLab migration made them necessary anyway). GitLab, 10 private
   repos: Developer member, `main` protected (push/merge = Maintainers only), merge method fast-forward
   with squash encouraged. GitHub, 5 public repos (mit_65840, expense-splitter, arc-runner-podman,
   public-homelab-fork, 8086_dissasembler): write collaborator, plus a `protect-main` ruleset requiring
   a PR with one approving review (authors can't self-approve), force-push and deletion blocked, and a
   repository-admin bypass so the operator still pushes `main` directly. The contract is identical
   everywhere: the bot works on `hermes/*` branches, opens a PR/MR, and only the operator merges.
   The GitLab PAT expires ~2027-07-06 (gitlab.com caps tokens at 365 days; expiry warnings email the
   bot's account).
8. ~~**Read-only k8s RBAC** for diagnosis/alerting (why an app is down, whether a dep needs a bump). A
   dedicated read-only ServiceAccount + token — a conscious reversal of `automountServiceAccountToken:
   false`, and the "read-only SA if a monitor needs the API" item already on the security wish list.
   RBAC has no deny, so it's an *allowlist* of resources (pods, deployments, events, nodes, …) that
   simply omits `secrets`, not "read-all minus secrets".~~ Done 2026-07-07, as a dedicated
   `hermes-agent` SA with two ClusterRoleBindings: the built-in `view` ClusterRole plus a hand-rolled
   `hermes-agent-view-extras` for what `view` misses, cluster-scoped core (nodes, PVs, storageclasses,
   volumeattachments) and the CRD groups the repo actually uses (Argo, Longhorn including the
   backup/recurringjob kinds, Cilium, Gateway API, Envoy Gateway, CNPG, MetalLB, Tailscale,
   SealedSecrets). Verbs `get/list/watch` only, no `nodes/proxy`, no `secrets` anywhere
   (`kubernetes/apps/hermes-agent/templates/rbac.yaml`). We chose `view`+extension over a fully
   hand-rolled allowlist: `aggregate-to-view` drift is opt-in and rare (only cert-manager aggregates
   here today), the extras file stays the single audited grant in git, and the PR-review gate, not
   RBAC, is the real control against a malicious CRD leaking secrets into readable objects. Accepted
   residual read channels: configmaps and `pods/log` (SealedSecrets keep real secrets out of the
   former; the latter is half the diagnostic value, so tolerated). Verified with
   `kubectl auth can-i --list --as=system:serviceaccount:hermes-agent:hermes-agent` plus negative
   probes, then end-to-end: the agent installed kubectl itself (userspace Homebrew on the PVC) and
   read the cluster over Telegram. One gotcha needed a second commit: Hermes's terminal sandbox
   rebuilds each shell's env from a cached login-shell snapshot and strips secret-looking vars
   (`tools/env_passthrough.py` in the image), so the kubelet-injected `KUBERNETES_SERVICE_*` vars
   never reach its shells and kubectl's in-cluster autodetection can't fire (first theory blamed s6,
   wrong, verified via `/proc/*/environ`). Fixed declaratively with the `hermes-agent-kubeconfig`
   ConfigMap, server `kubernetes.default.svc` and `tokenFile` pointing at the projected token so
   kubelet rotation keeps working, subPath-mounted at `/opt/data/home/.kube/config`. Mind the two
   HOMEs: the container's `HOME` is `/opt/data`, but the terminal sandbox's is `/opt/data/home`
   (dotfiles, brew, `.kube` all live there).
9. Chip away at the wish list and add more jobs; revisit the MoA experiment and a per-lab subscription
   once the base system feels solid (see Decisions).
