# Firewall4 Generic Fullcone Restoration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore the necessary generic firewall4 fullcone integration while keeping the unnecessary Broadcom-specific firewall4 backend disabled.

**Architecture:** Keep the existing patch series as the source of truth. Rebase the single stale configuration context line in `999-01`, change the preparation filter to copy that patch again, and leave `999-02` explicitly excluded. All behavioral validation and builds run on GitHub-hosted Linux runners; macOS is limited to inspection, editing, and Git operations.

**Tech Stack:** POSIX shell, OpenWrt 24.10 package patches, firewall4/ucode, GitHub Actions, GitHub CLI

---

### Task 1: Record the necessity decision

**Files:**
- Modify: `docs/superpowers/specs/2026-08-08-firewall4-fullcone-restoration-design.md`
- Create: `docs/superpowers/plans/2026-08-10-firewall4-generic-fullcone-restoration.md`

- [ ] **Step 1: Record the generic fullcone evidence**

Document that upstream firewall4 lacks this integration, all non-minimal seeds select `kmod-nft-fullcone`, and the supporting kernel/userspace stack is already enabled.

- [ ] **Step 2: Record the BCM rejection**

Document that `999-02` is a Broadcom-derived, IPv4-only alternative backend with no demonstrated need or performance benefit on MediaTek MT7988.

- [ ] **Step 3: Verify the documentation scope by inspection**

Run:

```bash
git diff --check
git diff -- docs/superpowers/specs/2026-08-08-firewall4-fullcone-restoration-design.md docs/superpowers/plans/2026-08-10-firewall4-generic-fullcone-restoration.md
```

Expected: exit 0; the design says restore only `999-01`, keep `999-02` disabled, and defer BCM cleanup.

### Task 2: Restore only the generic firewall4 patch

**Files:**
- Modify: `patches/packages/firewall/firewall4_patches/999-01-firewall4-add-fullcone-support.patch`
- Modify: `build/02_prepare.sh`

- [ ] **Step 1: Confirm the RED evidence**

Run against GitHub metadata only:

```bash
gh run view 26240675942 --repo MoozIiSP/BPI-R4-Firmware --log-failed
```

Expected: the firewall4 package preparation fails because the WAN-zone hunk in `999-01` expects `option forward DROP` while the pinned firewall4 source uses `option forward REJECT`.

- [ ] **Step 2: Rebase only the stale context line**

In `999-01-firewall4-add-fullcone-support.patch`, change the WAN-zone context from:

```diff
 option forward        DROP
```

to:

```diff
 option forward        REJECT
```

Do not change either added fullcone default.

- [ ] **Step 3: Restore only `999-01` in the preparation filter**

Change the firewall4 patch copy command in `build/02_prepare.sh` from two exclusions to only:

```sh
    ! -name '999-02-firewall4-add-bcm-fullconenat-support.patch' \
```

Update the status message to state that the BCM-specific firewall4 patch remains skipped pending its necessity audit.

- [ ] **Step 4: Verify the minimal diff by inspection**

Run:

```bash
git diff --check
git diff -- build/02_prepare.sh patches/packages/firewall/firewall4_patches/999-01-firewall4-add-fullcone-support.patch
```

Expected: exit 0; one patch context line changes, only the `999-01` filter is removed, and `999-02` remains excluded. This is inspection, not a local patch application or test.

- [ ] **Step 5: Commit the restoration**

```bash
git add build/02_prepare.sh patches/packages/firewall/firewall4_patches/999-01-firewall4-add-fullcone-support.patch docs/superpowers/specs/2026-08-08-firewall4-fullcone-restoration-design.md docs/superpowers/plans/2026-08-10-firewall4-generic-fullcone-restoration.md
git commit -m "fix: restore generic firewall4 fullcone support"
```

### Task 3: Validate on GitHub Actions

**Files:**
- Verify: `.github/workflows/validate.yml`

- [ ] **Step 1: Push the feature branch**

```bash
git push origin codex/conservative-patch-qemu
```

- [ ] **Step 2: Dispatch repository validation**

```bash
gh workflow run validate.yml --repo MoozIiSP/BPI-R4-Firmware --ref codex/conservative-patch-qemu
```

- [ ] **Step 3: Verify the validation run**

Use `gh run view` to inspect every job and step.

Expected: all jobs and steps succeed. On failure, read the complete failed job log and stop at the first substantive error.

### Task 4: Build the complete package repository remotely

**Files:**
- Verify: `.github/workflows/build-packages.yml`

- [ ] **Step 1: Dispatch the package build**

```bash
gh workflow run build-packages.yml --repo MoozIiSP/BPI-R4-Firmware --ref codex/conservative-patch-qemu -f mtk_feed_release=24.10
```

- [ ] **Step 2: Verify jobs and steps**

Use `gh run view` to confirm the package preparation and repository build complete successfully.

Expected: every required step succeeds, including application of `999-01`; `999-02` is not copied.

- [ ] **Step 3: Verify the artifact**

Use the GitHub API to confirm `bpi-r4-full-packages` exists, is not expired, and has nonzero size. Downloading or inspecting the archive on macOS is excluded.

Expected: the artifact contains the workflow-produced package ZIP and SHA-256 checksum and reports a nonzero artifact size.

- [ ] **Step 4: Stop on failure**

If any job fails or is cancelled, read the complete failed job log, identify the first substantive error, and report it before making another source change.
