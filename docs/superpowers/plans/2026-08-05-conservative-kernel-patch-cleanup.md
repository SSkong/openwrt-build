# Conservative Kernel Patch Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove only the confirmed Linux 6.6.144 duplicate TCP patch and the dead, unused theme clone, then prove the normal BPI-R4 full SD build and its ZIP/SHA256 bundle pass on GitHub Actions.

**Architecture:** Add a remote policy check first so the known-obsolete inputs produce a deliberate red result. Make the two surgical removals, add an on-runner bundle-integrity gate to the existing authoritative device workflow, then run validation and the same `full / sd / MTK feed / 24.10` build remotely. Linux 6.6.144 still lacks the semantics of TCP patches `630-01` through `630-03`, so those three remain until separate evidence justifies removal.

**Tech Stack:** GitHub Actions, Bash, `gh`, OpenWrt 24.10, Linux 6.6, ZIP, SHA256

---

## File map

- Modify `.github/workflows/validate.yml`: enforce the evidence-backed cleanup policy on a Linux runner.
- Modify `.github/workflows/build.yml`: verify the generated ZIP and SHA256 file before artifact upload.
- Modify `build/01_clone.sh`: remove the unused `SAENE/luci-theme-design` variable and background clone.
- Delete `patches/kernel/tcp/630-04-v6.7-tcp-defer-regular-ACK-while-processing-socket-backlog.patch`: Linux 6.6.144 already supplies this behavior.
- Preserve `patches/kernel/tcp/630-01-*`, `630-02-*`, and `630-03-*`: source inspection shows their ownership/release-callback changes are not present in Linux 6.6.144.

All test, build, checksum, and artifact-content commands below run in GitHub Actions. The local macOS checkout is used only for editing, Git operations, workflow dispatch, and reading remote status/logs.

### Task 1: Add a remote cleanup-policy test and capture red evidence

**Files:**
- Modify: `.github/workflows/validate.yml`

- [ ] **Step 1: Append the cleanup-policy job**

Add this job after `patch-structure`:

```yaml
  conservative-cleanup-policy:
    runs-on: ubuntu-latest
    name: Conservative cleanup policy
    steps:
      - uses: actions/checkout@v4

      - name: Reject confirmed obsolete inputs
        shell: bash
        run: |
          set -euo pipefail
          failed=0

          obsolete_tcp_patch="patches/kernel/tcp/630-04-v6.7-tcp-defer-regular-ACK-while-processing-socket-backlog.patch"
          if [ -e "$obsolete_tcp_patch" ]; then
            echo "ERROR: Linux 6.6.144 already contains TCP_ACK_DEFERRED and tcp_backlog_ack_defer: $obsolete_tcp_patch"
            failed=1
          fi

          if grep -RFn 'SAENE/luci-theme-design' build; then
            echo "ERROR: deleted and unused luci-theme-design repository is still referenced"
            failed=1
          fi

          if [ "$failed" -ne 0 ]; then
            exit 1
          fi

          echo "Confirmed obsolete inputs are absent."
```

- [ ] **Step 2: Commit and push the deliberately failing policy test**

```bash
git add .github/workflows/validate.yml
git commit -m "test: enforce conservative patch cleanup policy"
git push -u origin codex/conservative-patch-qemu
```

- [ ] **Step 3: Dispatch validation on GitHub Actions**

```bash
gh workflow run validate.yml \
  --repo MoozIiSP/BPI-R4-Firmware \
  --ref codex/conservative-patch-qemu
gh run list \
  --repo MoozIiSP/BPI-R4-Firmware \
  --workflow validate.yml \
  --branch codex/conservative-patch-qemu \
  --limit 1
```

Expected: the newest run reaches `failure`; `Conservative cleanup policy` reports both the obsolete TCP patch and the dead repository reference. All commands that evaluate repository content run on Ubuntu, not macOS.

- [ ] **Step 4: Record the exact red run ID in the plan progress notes**

Use remote metadata only:

```bash
CLEANUP_RED_RUN_ID="$(gh run list --repo MoozIiSP/BPI-R4-Firmware \
  --workflow validate.yml --branch codex/conservative-patch-qemu \
  --event workflow_dispatch --limit 1 --json databaseId --jq '.[0].databaseId')"
gh run view "$CLEANUP_RED_RUN_ID" \
  --repo MoozIiSP/BPI-R4-Firmware \
  --json url,status,conclusion,jobs
```

Expected: `conclusion` is `failure`, and the failed step is `Reject confirmed obsolete inputs`.

### Task 2: Remove only the two confirmed obsolete inputs

**Files:**
- Modify: `build/01_clone.sh:66-74,127-135`
- Delete: `patches/kernel/tcp/630-04-v6.7-tcp-defer-regular-ACK-while-processing-socket-backlog.patch`

- [ ] **Step 1: Delete only TCP patch `630-04`**

```bash
git rm patches/kernel/tcp/630-04-v6.7-tcp-defer-regular-ACK-while-processing-socket-backlog.patch
```

Do not delete `630-01`, `630-02`, or `630-03`. Linux 6.6.144 contains `TCP_ACK_DEFERRED`/`tcp_backlog_ack_defer`, but still has the older conditional `sock_release_ownership()` and lacks the added `release_cb()` call in `__sk_flush_backlog()`.

- [ ] **Step 2: Remove the dead theme repository declaration and clone**

Change this block:

```bash
OPENWRT_ADD_REPO="https://github.com/QiuSimons/OpenWrt-Add.git"
DOCKERMAN_REPO="https://github.com/lisaac/luci-app-dockerman"
DOCKER_LIB_REPO="https://github.com/lisaac/luci-lib-docker"
LUCI_THEME_DESIGN_REPO="https://github.com/SAENE/luci-theme-design"
```

to:

```bash
OPENWRT_ADD_REPO="https://github.com/QiuSimons/OpenWrt-Add.git"
DOCKERMAN_REPO="https://github.com/lisaac/luci-app-dockerman"
DOCKER_LIB_REPO="https://github.com/lisaac/luci-lib-docker"
```

Change this clone block:

```bash
  clone_repo "$OPENWRT_ADD_REPO" "master" OpenWrt-Add &
  clone_repo "$DOCKERMAN_REPO" "master" dockerman &
  clone_repo "$DOCKER_LIB_REPO" "master" docker_lib &
  clone_repo "$LUCI_THEME_DESIGN_REPO" "master" luci_theme_design_repo &
  wait
```

to:

```bash
  clone_repo "$OPENWRT_ADD_REPO" "master" OpenWrt-Add &
  clone_repo "$DOCKERMAN_REPO" "master" dockerman &
  clone_repo "$DOCKER_LIB_REPO" "master" docker_lib &
  wait
```

- [ ] **Step 3: Commit the surgical cleanup**

```bash
git add build/01_clone.sh patches/kernel/tcp
git commit -m "fix: drop obsolete TCP patch and dead theme clone"
git push
```

- [ ] **Step 4: Re-run the remote policy suite**

```bash
gh workflow run validate.yml \
  --repo MoozIiSP/BPI-R4-Firmware \
  --ref codex/conservative-patch-qemu
```

Expected: `Conservative cleanup policy` passes. If another job fails, inspect its complete GitHub job log and stop; do not widen cleanup based only on a failed hunk.

### Task 3: Make artifact integrity an explicit build gate

**Files:**
- Modify: `.github/workflows/build.yml:56-66`

- [ ] **Step 1: Add the on-runner artifact verification step**

Insert this step between `Build firmware` and `Upload firmware bundle`:

```yaml
      - name: Verify firmware bundle
        shell: bash
        run: |
          set -euo pipefail
          bundle="artifacts/bpi-r4-${BUILD_VARIANT}-${BUILD_MEDIA}.zip"
          checksum="${bundle}.sha256sum"

          test -s "$bundle"
          test -s "$checksum"
          sha256sum -c "$checksum"

          unzip -t "$bundle"
          unzip -Z1 "$bundle" | grep -Eq '/openwrt-mediatek-filogic-bananapi_bpi-r4.*(sysupgrade|sdcard|initramfs|kernel)'

          echo "Verified bundle: $bundle"
          echo "Verified checksum: $checksum"
```

This deliberately verifies bytes and archive contents on the Ubuntu builder before `actions/upload-artifact`; downloading and checking the artifact on the Mac is not part of the plan.

- [ ] **Step 2: Commit and push the integrity gate**

```bash
git add .github/workflows/build.yml
git commit -m "ci: verify firmware bundle before upload"
git push
```

- [ ] **Step 3: Run remote workflow validation**

```bash
gh workflow run validate.yml \
  --repo MoozIiSP/BPI-R4-Firmware \
  --ref codex/conservative-patch-qemu
```

Expected: all jobs pass, including workflow YAML parsing and Bash syntax checks.

### Task 4: Prove the repaired BPI-R4 baseline remotely

**Files:**
- No source changes

- [ ] **Step 1: Dispatch the authoritative build with the baseline inputs**

```bash
gh workflow run build.yml \
  --repo MoozIiSP/BPI-R4-Firmware \
  --ref codex/conservative-patch-qemu \
  -f variant=full \
  -f media=sd \
  -f enable_mtk_feed=true \
  -f mtk_feed_release=24.10
```

- [ ] **Step 2: Obtain and watch the new run**

```bash
BASELINE_BUILD_RUN_ID="$(gh run list \
  --repo MoozIiSP/BPI-R4-Firmware \
  --workflow build.yml \
  --branch codex/conservative-patch-qemu \
  --event workflow_dispatch \
  --limit 1 --json databaseId --jq '.[0].databaseId')"
gh run watch "$BASELINE_BUILD_RUN_ID" \
  --repo MoozIiSP/BPI-R4-Firmware \
  --exit-status
```

Expected: every step, including `Build firmware`, `Verify firmware bundle`, and `Upload firmware bundle`, succeeds. If the run fails or is cancelled, read the complete failed job log, identify the first substantive error, and stop without deleting further patches.

- [ ] **Step 3: Inspect the remote run and artifact metadata**

```bash
gh run view "$BASELINE_BUILD_RUN_ID" \
  --repo MoozIiSP/BPI-R4-Firmware \
  --json url,headSha,status,conclusion,jobs
gh api \
  "repos/MoozIiSP/BPI-R4-Firmware/actions/runs/$BASELINE_BUILD_RUN_ID/artifacts" \
  --jq '.artifacts[] | [.name, .expired, .size_in_bytes] | @tsv'
```

Expected: exactly one row named `bpi-r4-full-sd`, with `expired` equal to `false` and `size_in_bytes` greater than zero.

The successful `Verify firmware bundle` step is the evidence that both `bpi-r4-full-sd.zip` and `bpi-r4-full-sd.zip.sha256sum` existed, the checksum matched, the ZIP was structurally valid, and it contained at least one BPI-R4 image.

- [ ] **Step 4: Record the Gate 1 result**

Add the run URL, commit SHA, artifact name, artifact size, and the successful integrity-step outcome to the task handoff. Gate 1 is complete only after all five values are present.

## Stop conditions

- Do not proceed to QEMU workflow implementation until Task 4 is green.
- Do not delete any additional TCP or performance patch merely because it is old.
- On a new patch failure, use the first substantive GitHub log error and upstream source semantics as evidence before proposing another removal.
- Never execute `bash build/*.sh`, `make`, patch dry-runs, archive checks, or QEMU locally on macOS.
