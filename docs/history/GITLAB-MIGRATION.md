# GitHub to GitLab migration

Status: executed 2026-07-06, cutover clean (see execution notes). Moved the homelab repo from
GitHub to GitLab. Only Argo consumes this repo, so the whole risk surface was one re-point plus not
letting Argo prune against a wrong desired state mid-switch.

## Why

We want branch protection on `main` (force pull requests, no direct push) ahead of the Hermes agent
PR write-path: an isolated bot account that opens PRs and never pushes to `main`.

GitHub gates that behind paid org tiers for a private repo. The live UI refused to enforce branch
protection rules until "a GitHub Team or Enterprise organization account", and rulesets on a private
personal repo need Team org as well. So enforcing branch protection on GitHub meant creating an org,
restructuring the repo under it, and paying per user, ongoing.

GitLab Free includes protected branches on private projects (prevent force-push and deletion, restrict
who can push and merge, require a merge request) with no org, and real member roles on a personal
namespace (Reporter is read-only), which GitHub personal repos do not have. That covers both the
branch protection and the future read-only bot member.

Decisions:
- GitLab.com, personal namespace `michael-muzafarov`, no group. A group only pays off when bundling
  several repos under one access policy; not worth the complexity for one repo.
- Only this repo moves. `expense-splitter` stays on GitHub with its Actions runner (`gha`); mixed
  hosting is fine.

## What authenticates, and what moves

- Argo is the only consumer. It pulled GitHub over SSH with a UI-added credential (the operator's own
  key). For GitLab we minted a dedicated read-only deploy key (`~/.ssh/argo-gitlab-deploy`, no
  passphrase) instead, and committed it as a SealedSecret labeled
  `argocd.argoproj.io/secret-type: repository`
  (`kubernetes/apps/argocd/templates/gitlab-repo-sealedsecret.yaml`), so the GitLab credential is
  declarative. Argo matches credentials to repos by URL. The old UI credential can be deleted once
  GitHub is archived.
- `argocd-image-updater` uses the `argocd` write-back method (it patches the live Application's params
  on a digest change and redeploys), not git write-back, so Argo needs only read access. It does not
  commit to the repo.
- `repoURL` lives in two files: `kubernetes/apps/argocd/values.yaml` (root app) and
  `kubernetes/apps/app-of-apps/templates/app-of-apps.yaml` (the child template, one edit re-points all
  child apps).

## Why the switch is safe

- We push an identical mirror (full history) to GitLab and put the same repoURL-change commit on both
  remotes. Desired state is byte-identical whichever remote Argo reads, so the cutover renders the same
  resources, zero diff, nothing to prune.
- The real nuke risk is Argo reading a valid but empty or wrong tree and pruning against it. Pruning is
  the only destructive op, and it cascades because every child Application carries the
  `resources-finalizer`. An empty read happens if `targetRevision: HEAD` resolves to the wrong default
  branch on GitLab, or if the switch lands before the push finishes.
- Guards for the cutover window:
  - Turn prune off everywhere so a bad read cannot delete anything. Set `suspended: true` on each app
    in `app-of-apps/values.yaml` (the template drops the `automated` block), and set `prune: false` +
    `selfHeal: false` on the root app in `argocd/values.yaml`. Flip both back after the switch settles.
  - Pin `targetRevision` from `HEAD` to `main` and verify GitLab has the full tree before flipping
    repoURL, so the wrong read does not happen in the first place.
- Auth failure alone does not prune. If Argo cannot reach the repo it errors (ComparisonError) and
  changes nothing.

## Steps

1. Mirror to GitLab. `git remote add gitlab git@gitlab.com:michael-muzafarov/homelab.git` then
   `git push gitlab --all --tags`. Verify the file tree and that the default branch is `main`.
2. Add the GitLab repo credential in the Argo UI (same SSH key), matching the GitLab URL exactly.
3. Turn off destructive sync and confirm it applied: `suspended: true` on each child in
   `app-of-apps/values.yaml`, `prune: false` + `selfHeal: false` on the root in `argocd/values.yaml`,
   push to `main`. The `argocd` app renders the root, so make sure the root's `prune: false` is live
   before the next step.
4. Switch. Pin `targetRevision: HEAD` to `main` and flip repoURL to GitLab in both files, commit to
   both remotes. Argo re-points to GitLab and reads identical content, zero diff.
5. Verify apps are green against GitLab.
6. Re-enable sync: `suspended` back off, `prune`/`selfHeal` back to `true`.
7. Re-point the working copy: `git remote set-url origin git@gitlab.com:michael-muzafarov/homelab.git`.
   Keep this directory; Claude Code memories are keyed to its path.
8. Protect `main` on GitLab (require a merge request before merging). Archive the GitHub repo.

## Execution notes (2026-07-06)

- The plan's assumption that "the argocd app renders the root" turned out to be wrong. The root
  `app-of-apps` Application is not in git at all: it was `kubectl apply`ed once at bootstrap, carries
  no Argo tracking label, and the `applications:` block in `kubernetes/apps/argocd/values.yaml` is
  dead config. The `argo-cd` chart has no `applications` value (that feature lives in the separate
  `argocd-apps` chart, which is not a dependency), and Helm ignores unknown values silently, so the
  argocd app showed Synced while rendering nothing for the root. We caught it when the root-app guard
  commit synced green but the live object kept `prune: true`.
- Consequence: every root-app change (the prune/selfHeal guard, the repoURL flip, the restore) was a
  manual `kubectl apply` against the live object. The git edits to `argocd/values.yaml` were kept so
  the file describes the intended state, but they do nothing today.
- TODO: adopt the root declaratively. Add `argocd-apps` as a dependency of the argocd chart and move
  the `applications:` block under its values key, rendered with `finalizers: []` so a pruned root
  orphans children in place instead of cascade-deleting them. Bootstrap on a fresh cluster then
  becomes `helm template kubernetes/apps/argocd | kubectl apply -f -` and the circle closes itself.
- Cutover commits, each pushed to GitHub and GitLab in lockstep: `2efcf2f` sealed GitLab repo
  credential, `aea3f1c` root guard (dead config, see above), `1f3e155` suspend all children,
  `02778f4` repoURL switch + pin `main`, `c01de1c`/`2016252` reverts of the two guards.
- After suspension two apps showed OutOfSync; both were pre-existing mechanisms, not migration
  diffs, and nothing was flagged for pruning. cilium: the chart regenerates hubble/CA TLS secrets on
  every render, `selfHeal: true` continuously re-syncs the churn and suspension merely exposed it.
  app-of-apps: the live longhorn child Application carries two Argo-added
  `pre-delete-finalizer.argocd.argoproj.io` finalizers (the Longhorn chart has uninstall hooks) that
  the render lacks and an apply cannot remove; spec content was byte-identical.

## Known post-migration warts

- **UI "Unable to load data ... git@github.com: Permission denied (publickey)".** Cosmetic, not a
  deploy failure. Apps still carry pre-cutover entries in `.status.history` whose `source.repoURL` is
  the old GitHub URL. Opening an app (the History/rollback panel) makes the UI request revision
  metadata for those old commits, and repo-server fails to fetch them because the GitHub key is gone
  by design. Deploys are unaffected, they run against GitLab. `.status.history` is a 10-entry ring
  buffer, so the GitHub entries age out on their own as each app re-syncs. `.status` is Argo-owned,
  so there is no clean declarative way to clear it early, and it is not worth doing imperatively.
