# SearXNG

Private search discovery for Hermes. The service is cluster-internal only: there is no HTTPRoute,
LoadBalancer, or public DNS record. A Cilium policy permits ingress from the `searxng` and
`hermes-agent` namespaces.

## Search policy

The default engine set is the combination validated from the home ISP egress:

- Google CSE
- Startpage

Yahoo is intentionally absent because its upstream intermittently closes otherwise valid HTTP
requests. One failure suspends the engine and amplifies a transient disconnect into several sparse
aggregate searches. Brave and DuckDuckGo are also absent after repeated 429 and CAPTCHA failures.
SearXNG's suspension policy preserves results from surviving engines rather than immediately retrying
blocked engines. Both HTML and JSON output are enabled; Hermes uses JSON.

The image records its CalVer/revision tag for readability and is pinned to the corresponding amd64
manifest digest for reproducibility. Renovate may update it, but updates need a normal exact-head
review and a search smoke test because upstream engine behavior changes frequently.

## Hermes cutover

The deployment does not rewrite dashboard-owned Hermes state. After Argo reports the app healthy,
run a search from the Hermes pod before changing configuration:

```sh
curl -fsS --get   --data-urlencode 'q=Kubernetes documentation'   --data 'format=json'   http://searxng.searxng.svc.cluster.local:8080/search
```

The Hermes deployment declares the endpoint as `HERMES_SEARXNG_SERVICE_URL`. This deliberately
avoids the recognized `SEARXNG_URL`, which could select SearXNG before normal-use quality is proven.
Use `searxng-search "QUERY" --engines "google cse,startpage"` for explicit searches without changing
the configured backend. Cutover remains a separate dashboard-owned configuration change. After
cutover, start a fresh Hermes session and verify one routine query and one exact-error query through
the web search tool. SearXNG is search-only; known-URL extraction continues through direct HTTP,
Jina, Keenable fetch, or the browser. Keenable and Codex search remain manual fallbacks until Hermes
has provider-level fallback routing.

## Operations and rollback

Health endpoint: `http://searxng.searxng.svc.cluster.local:8080/healthz`.

If quality or reliability regresses, revert `web.search_backend` and use a fresh Hermes session.
Reverting the app-of-apps entry removes the deployment, service, policy, config, and sealed secret.
No persistent volume or search history is retained.
