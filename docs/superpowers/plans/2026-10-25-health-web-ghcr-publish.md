# health-web GHCR Publish Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every merge to `main` that touches `apps/health-web/**` builds and publishes multi-arch `health-backend` / `health-frontend` images to GHCR from this repo's own GitHub Actions workflow.

**Architecture:** A single workflow `.github/workflows/publish-ghcr-images.yml` runs `go vet` + `go test` for the API, then a two-entry matrix (backend, frontend) builds `linux/amd64,linux/arm64` with Buildx. It pushes only on `main` and runs build-only on PRs. After pushing, it checks the published index against the contract `nacfson_pipeline`'s `update-project-images` skill enforces. The API Dockerfile cross-compiles Go natively, so the arm64 leg avoids slow QEMU compilation.

**Tech Stack:** GitHub Actions, `docker/setup-qemu-action@v3`, `docker/setup-buildx-action@v3`, `docker/login-action@v3`, `docker/metadata-action@v5`, `docker/build-push-action@v6`, `actions/setup-go@v5`, Go 1.23 (Dockerfile) / `go 1.22.0` (go.mod), nginx 1.27-alpine.

**Spec:** No separate spec doc. Requirements come from the 2026-10-25 diagnosis (this repo has never had an image-publishing workflow; the only registered workflow is "Copilot code review"). The consumer contract comes from `nacfson_pipeline/.agents/skills/update-project-images/` and `nacfson_pipeline/deploy/projects/health/workloads/*.yaml`, copied into Global Constraints below.

## Global Constraints

- Image repositories, exactly: `ghcr.io/nacfson/health-backend` and `ghcr.io/nacfson/health-frontend` (the names pinned in `nacfson_pipeline/deploy/projects/health/workloads/{backend,frontend}-deployment.yaml`).
- Every published tag is an OCI index containing both `linux/amd64` and `linux/arm64` (vps-k3s is arm64 Ampere; the resolver rejects single-arch manifests).
- Tags: 7-character commit SHA (resolver `_tag_candidates` tries `sha[:7]` first), plus `latest` only when built from `main`.
- Image config labels: `org.opencontainers.image.source` = `https://github.com/nacfson/nacfson_health`; `org.opencontainers.image.revision` = full 40-char commit SHA (the resolver blocks on revision mismatch).
- Publish job display names must contain the role word `backend` / `frontend` (the resolver matches Actions jobs by `role in job.name.lower()`). No other job name may contain those words.
- Push only when `github.event_name != 'pull_request'` **and** `github.ref == 'refs/heads/main'`. PRs and dispatches from other branches build without pushing.
- Registry auth: `secrets.GITHUB_TOKEN` with `permissions: packages: write`. No PAT.
- Backend image declares `ExposedPorts` `8080/tcp` (Deployment `containerPort: 8080`).
- Do not modify `nacfson_pipeline`, Flutter paths (`lib/`, `ios/`, `android/`), or app runtime behavior.
- The local Docker socket is not accessible to this user (`permission denied`). Image builds are verified in CI, not locally. Do not change socket or group permissions.

## Out of Scope (follow-ups, do not do here)

- Frontend runtime compatibility with the pipeline Deployment: port `8080` vs nginx `listen 80`, non-root UID 10001 + `readOnlyRootFilesystem` vs default nginx pid path, nginx upstream `health-api:8080` vs Service `health-backend`, startupProbe `/api/auth/config` (no such route).
- Backend Deployment env mismatch (`GATEWAY_AUTH_URL`/`DB_TOKEN` vs `CENTRAL_AUTH_URL`/`CENTRAL_AUTH_INTERNAL_URL`/`AUTH_SESSION_INTERNAL_TOKEN`).
- The digest-pin PR in `nacfson_pipeline` (done afterwards with its `update-project-images` skill).

## Review Focus

1. **Package pre-exists from a manual push and isn't linked to this repo** → the first `main` push fails with `denied: permission_denied: write_package`. Expected: the operator grants this repo Write under the package's "Manage Actions access" and re-runs. Pinned in Task 3 Step 4.
2. **PR or non-main dispatch must never overwrite `latest` or SHA tags.** Expected: build runs, nothing is pushed. Pinned in Task 2 (`PUBLISH` gate) and Task 3 Step 2 (log check).
3. **Flutter-only or docs-only commits must not trigger image builds**, but edits to the workflow file itself must. Pinned in Task 2 (`paths`) and Task 3 Step 6.
4. **arm64 Go compile under QEMU is slow enough to time out or crawl.** Expected: Go cross-compiles on the runner's native arch. Pinned in Task 1.
5. **A published image that violates the consumer contract** (missing arch, wrong revision/source label, wrong port) is caught by the run, not later by the pin PR. Pinned in Task 2's verify step and observed in Task 3 Step 3.

---

### Task 1: Cross-compile the API in its Dockerfile

**Files:**
- Modify: `apps/health-web/api/Dockerfile:4-12`

**Interfaces:**
- Consumes: Buildx automatic build args `BUILDPLATFORM`, `TARGETOS`, `TARGETARCH`.
- Produces: an API image whose `/app/api` and `/app/migrate` binaries match the target platform. Runtime stage, `WORKDIR /app`, `EXPOSE 8080`, `USER 65532:65532`, `CMD ["./api"]` are unchanged.

- [ ] **Step 1: Confirm the gap**

Run: `grep -nE 'BUILDPLATFORM|TARGETARCH' apps/health-web/api/Dockerfile`
Expected: no output (exit 1).

- [ ] **Step 2: Edit the build stage**

Change `FROM golang:1.23-bookworm AS build` to `FROM --platform=$BUILDPLATFORM golang:1.23-bookworm AS build`, add `ARG TARGETOS TARGETARCH` after `WORKDIR /src`, and replace `GOOS=linux` with `GOOS=$TARGETOS GOARCH=$TARGETARCH` in both `go build` commands. Keep `CGO_ENABLED=0 -trimpath -ldflags="-s -w"`.

- [ ] **Step 3: Verify the same cross-compile works outside Docker (stand-in for the build stage)**

Run:
```bash
cd apps/health-web/api
for a in amd64 arm64; do CGO_ENABLED=0 GOOS=linux GOARCH=$a go build -trimpath -ldflags="-s -w" -o /tmp/hw-$a/api ./cmd/api && file /tmp/hw-$a/api; done
```
Expected: `x86-64 ... statically linked` for amd64 and `ARM aarch64 ... statically linked` for arm64. The real Dockerfile build is verified in Task 3 Step 2.

- [ ] **Step 4: Commit**

```bash
git add apps/health-web/api/Dockerfile
git commit -m "build(health-web): cross-compile api for target platform in Dockerfile"
```

---

### Task 2: Publish workflow + docs

**Files:**
- Create: `.github/workflows/publish-ghcr-images.yml`
- Modify: `apps/health-web/README.md:113-123` ("Container" section)
- Modify: `docs/changelog-health-web-mvp.md` ("Ops remaining" item 1)
- Modify: `docs/features.md:3,10-17` (date line + health-web checklist)
- Modify: `AGENTS.md` ("Web (Option B)" bullet in 프로젝트 요약)

**Interfaces:**
- Consumes: Task 1's Dockerfile (contexts `apps/health-web/api`, `apps/health-web/frontend`; each uses its own `Dockerfile`).
- Produces: Actions jobs named `API tests`, `Publish backend image`, `Publish frontend image`. On `main`, tags `ghcr.io/nacfson/health-{backend,frontend}:{sha7,latest}`, and a step summary line `ghcr.io/nacfson/health-<role>@sha256:<64hex>` per role (the input format for `update-project-images`).

- [ ] **Step 1: Confirm the workflow does not exist yet**

Run: `ls .github/workflows/publish-ghcr-images.yml`
Expected: `No such file or directory`.

- [ ] **Step 2: Write the workflow**

Decisions (the implementer writes the YAML):
- `name: Publish health-web images`.
- `on`: `push` (branches `[main]`), `pull_request` (branches `[main]`), both with `paths: ["apps/health-web/**", ".github/workflows/publish-ghcr-images.yml"]`; plus `workflow_dispatch` with no inputs (always builds both).
- Top-level `permissions: { contents: read, packages: write }`.
- `concurrency: { group: "${{ github.workflow }}-${{ github.ref }}", cancel-in-progress: "${{ github.event_name == 'pull_request' }}" }`. Main runs queue and are never cancelled mid-publish.
- Job `api-tests`, `name: API tests`: checkout, `actions/setup-go@v5` with `go-version-file: apps/health-web/api/go.mod` and `cache-dependency-path: apps/health-web/api/go.sum`, then `go vet ./...` and `go test ./...` with `working-directory: apps/health-web/api`.
- Job `publish`, `name: Publish ${{ matrix.role }} image`, `needs: api-tests`, `strategy.fail-fast: false`, matrix `include`:
  - `{ role: backend,  image: health-backend,  context: apps/health-web/api,      port: "8080" }`
  - `{ role: frontend, image: health-frontend, context: apps/health-web/frontend, port: "80" }`. The current nginx port; changes to `8080` with the out-of-scope frontend fix.
- Job-level `env: { IMAGE: "ghcr.io/${{ github.repository_owner }}/${{ matrix.image }}", PUBLISH: "${{ github.event_name != 'pull_request' && github.ref == 'refs/heads/main' }}" }`.
- Steps: checkout → setup-qemu → setup-buildx → `docker/login-action@v3` (`registry: ghcr.io`, `username: ${{ github.actor }}`, `password: ${{ secrets.GITHUB_TOKEN }}`, `if: env.PUBLISH == 'true'`) → `docker/metadata-action@v5` (`id: meta`, `images: ${{ env.IMAGE }}`, tags `type=sha,prefix=,format=short` and `type=raw,value=latest,enable={{is_default_branch}}`, label `org.opencontainers.image.description=nacfson_health health-web ${{ matrix.role }}`, annotation `index:org.opencontainers.image.source=https://github.com/${{ github.repository }}`) → `docker/build-push-action@v6` (`id: build`, `context: ${{ matrix.context }}`, `platforms: linux/amd64,linux/arm64`, `push: ${{ env.PUBLISH == 'true' }}`, tags/labels/annotations from `meta`, `cache-from: type=gha,scope=${{ matrix.role }}`, `cache-to: type=gha,mode=max,scope=${{ matrix.role }}`) → verify step → summary step.
- metadata-action already emits `org.opencontainers.image.source` and `org.opencontainers.image.revision=${{ github.sha }}`. Do not set them by hand.
- Verify step (`if: env.PUBLISH == 'true'`, env `DIGEST: ${{ steps.build.outputs.digest }}`, `PORT: ${{ matrix.port }}`). This is the one non-obvious script:

```bash
set -euo pipefail
REF="${IMAGE}@${DIGEST}"
docker buildx imagetools inspect "$REF" --format '{{json .Image}}' > image.json   # map: "linux/<arch>" -> config
SRC="${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}"
for p in linux/amd64 linux/arm64; do
  jq -e --arg p "$p" 'has($p)' image.json >/dev/null || { echo "::error::$REF missing $p"; exit 1; }
  jq -e --arg p "$p" --arg v "$GITHUB_SHA" '.[$p].config.Labels["org.opencontainers.image.revision"] == $v' image.json >/dev/null \
    || { echo "::error::$p revision label != $GITHUB_SHA"; exit 1; }
  jq -e --arg p "$p" --arg v "$SRC" '.[$p].config.Labels["org.opencontainers.image.source"] == $v' image.json >/dev/null \
    || { echo "::error::$p source label != $SRC"; exit 1; }
  jq -e --arg p "$p" --arg v "${PORT}/tcp" '.[$p].config.ExposedPorts | has($v)' image.json >/dev/null \
    || { echo "::error::$p does not expose $PORT/tcp"; exit 1; }
done
echo "verified $REF"
```

- Summary step (`if: env.PUBLISH == 'true'`): append to `$GITHUB_STEP_SUMMARY` the role, the tags from `steps.meta.outputs.tags`, and the pin line `${IMAGE}@${DIGEST}`.

- [ ] **Step 3: Lint the workflow**

Run: `go run github.com/rhysd/actionlint/cmd/actionlint@v1.7.12 .github/workflows/publish-ghcr-images.yml`
Expected: no output, exit 0. If shellcheck findings appear for the verify script, fix them. Don't suppress them.

- [ ] **Step 4: Check the consumer-contract strings are present**

Run:
```bash
f=.github/workflows/publish-ghcr-images.yml
grep -c 'linux/amd64,linux/arm64' $f        # 1
grep -c "refs/heads/main" $f                # >=1
grep -c 'name: Publish ${{ matrix.role }} image' $f   # 1
grep -nE '^\s+name: ' $f | grep -iE 'backend|frontend'  # no output: role words reach job names only via matrix.role
```
Expected: counts as commented, last command prints nothing.

- [ ] **Step 5: Update docs**

- `apps/health-web/README.md` "Container": state that images are built by `.github/workflows/publish-ghcr-images.yml` on every `main` push touching `apps/health-web/**`. Cover the tags (`<sha7>`, `latest`), both platforms, PRs as build-only, and the step summary's `@sha256:` pin line. Pinning happens in `nacfson_pipeline` via `update-project-images` (`proj-health backend image: <Actions run link>`). Keep the local `docker build` example but drop the `192.168.219.100:5000` tag in favour of `ghcr.io/nacfson/health-backend:dev`.
- `docs/changelog-health-web-mvp.md` "Ops remaining" item 1 → `GHCR publish automated (publish-ghcr-images.yml); pin digests in nacfson_pipeline`.
- `docs/features.md`: set line 3 to `2026-10-25 (health-web GHCR publish)`. Under the health-web section add `- [x] GHCR 이미지 자동 배포 — .github/workflows/publish-ghcr-images.yml (main push, amd64+arm64, sha7/latest, PR build-only)`. Strike through the "registry push" part of line 16's unchecked item (`~~registry push~~`).
- `AGENTS.md` "Web (Option B)" bullet: append `이미지: GHCR \`ghcr.io/nacfson/health-{backend,frontend}\` via \`.github/workflows/publish-ghcr-images.yml\``.

- [ ] **Step 6: Commit**

```bash
git add .github/workflows/publish-ghcr-images.yml apps/health-web/README.md docs/changelog-health-web-mvp.md docs/features.md AGENTS.md
git commit -m "ci(health-web): publish health-backend/health-frontend multi-arch images to GHCR"
```

---

### Task 3: Roll out and prove it in CI

**Files:** none (unless a step fails and sends you back to Task 1/2).

**Interfaces:**
- Consumes: Task 2's job names and the step summary pin lines.
- Produces: the first `main`-built digests for both images, reported to the user for the `nacfson_pipeline` pin PR.

- [ ] **Step 1: Push branch and open PR**

```bash
git push -u origin <branch>
gh pr create --base main --title "ci(health-web): GHCR publish pipeline" --body "<summary + Review Focus list>"
```

- [ ] **Step 2: Verify the PR run is build-only and green**

Run: `gh pr checks <pr> --watch`, then `gh run view <run-id> --log | grep -iE 'pushing manifest|exporting manifest list|Login Succeeded'`
Expected: `API tests`, `Publish backend image`, and `Publish frontend image` all succeed. Both platforms build (`linux/arm64` appears in the logs). No `pushing manifest` and no `Login Succeeded` lines (login, verify, and summary steps are skipped).

- [ ] **Step 3: After the user merges, verify the main run published and self-verified**

Run: `gh run list -R nacfson/nacfson_health -w "Publish health-web images" -b main -L 1`, then `gh run view <id>`.
Expected: success. The verify step prints `verified ghcr.io/nacfson/health-backend@sha256:…` and the same for frontend. The step summary shows the tags `<sha7>` and `latest`.

- [ ] **Step 4: If push fails with `permission_denied: write_package`**

The package was created by an earlier manual push and isn't linked to this repo. Ask the user to open GitHub → Packages → `health-backend` (and/or `health-frontend`) → Package settings → Manage Actions access → add `nacfson/nacfson_health` with **Write**. Then `gh run rerun <id> --failed` and repeat Step 3. Do not switch to a PAT.

- [ ] **Step 5: Confirm the SHA tag resolves from outside Actions**

Run: `gh auth refresh -s read:packages` (user consent), then
`gh api /users/nacfson/packages/container/health-backend/versions --jq '.[0].metadata.container.tags'`
Expected: includes the merge commit's 7-char SHA and `latest`. Repeat for `health-frontend`.

- [ ] **Step 6: Path-filter negative check (next unrelated commit)**

After the next `main` commit that touches only `lib/` or `docs/`, run `gh run list -w "Publish health-web images" -L 3`.
Expected: no new run for that commit.

- [ ] **Step 7: Hand off**

Report to the user: run URL, both `@sha256:` pin lines, and the ready-to-paste input for `nacfson_pipeline`:
```text
proj-health backend image: <Actions run URL>
proj-health frontend image: <Actions run URL>
```
Also remind them of the Out of Scope runtime mismatches that must be fixed before the frontend pin is useful.
