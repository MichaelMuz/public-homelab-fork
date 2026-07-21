# Blog

## Publication path

```text
Emacs/Org -> ox-hugo -> Hugo + PaperMod -> GitHub Actions -> GHCR -> nginx in Kubernetes
```

The public [`MichaelMuz/blog`](https://github.com/MichaelMuz/blog) repository owns
Org source, generated Markdown when committed, Hugo configuration, the pinned
PaperMod version, and static assets. Drafts live on branches. Merging to `main`
builds and publishes `ghcr.io/michaelmuz/blog:latest`.

This repository owns the Kubernetes runtime and public route at
`blog.michaelmuzafarov.dev`. Argo CD Image Updater follows the GHCR tag by digest
through the `site.image.name` and `site.image.tag` Helm parameters.

## Updates and rollback

Content, Hugo, and PaperMod changes are reviewed in `MichaelMuz/blog`. Before
publishing dependency changes, verify the home page, posts, RSS, tags, and archive
pages.

Rollback is a revert in `MichaelMuz/blog`: the rebuilt image republishes `latest`
and Image Updater pins the new digest.
