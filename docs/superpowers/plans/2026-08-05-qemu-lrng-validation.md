# QEMU and LRNG Remote Validation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and boot the generic Linux patch stack in an ARM64 OpenWrt QEMU guest, repeat with all 27 LRNG patches, and build a separately named optional BPI-R4 LRNG SD image.

**Architecture:** Move the existing generic patch-family selection into one strict helper used by both the BPI-R4 and `armsvirt/64` builders. A guest init script emits deterministic markers and powers off; a host runner enforces a timeout and checks the serial log. GitHub Actions runs baseline first, permits LRNG only after baseline success, and uploads images, configs, and logs even when smoke checks fail.

**Tech Stack:** GitHub Actions, Bash, OpenWrt 24.10, Linux 6.6, QEMU ARM64 `virt`, virtio RNG, LRNG v59

---

## Preconditions and file map

Do not implement this plan until the conservative cleanup plan's Gate 1 full SD build is green.

- Create `build/apply-generic-kernel-patches.sh`: shared generic patch manifest and optional LRNG config.
- Modify `build/02_prepare.sh`: call the shared helper.
- Create `files/qemu-smoke/etc/init.d/qemu-smoke`: guest assertions and shutdown.
- Create `build/ci-qemu-build.sh`: remote `armsvirt/64` initramfs builder.
- Create `build/run-qemu-smoke.sh`: bounded QEMU runner and log assertions.
- Create `.github/workflows/qemu.yml`: baseline-first workflow.
- Modify `.github/workflows/validate.yml`: remote structural contract.
- Modify `.github/workflows/build.yml` and `build/ci-build.sh`: optional, non-default LRNG device bundle.

No build, syntax test, patch application, QEMU boot, random read, checksum check, or archive inspection may run on local macOS.

### Task 1: Add a remote QEMU contract test and capture red evidence

**Files:**
- Modify: `.github/workflows/validate.yml`

- [ ] **Step 1: Append the contract job**

```yaml
  qemu-validation-contract:
    runs-on: ubuntu-latest
    name: QEMU validation contract
    steps:
      - uses: actions/checkout@v4

      - name: Check QEMU validation structure
        shell: bash
        run: |
          set -euo pipefail
          required_files=(
            .github/workflows/qemu.yml
            build/apply-generic-kernel-patches.sh
            build/ci-qemu-build.sh
            build/run-qemu-smoke.sh
            files/qemu-smoke/etc/init.d/qemu-smoke
          )
          for path in "${required_files[@]}"; do
            test -f "$path" || {
              echo "ERROR: missing QEMU validation file: $path"
              exit 1
            }
          done
          test "$(find patches/kernel/lrng -maxdepth 1 -type f -name '*.patch' | wc -l)" -eq 27
          grep -Fq 'needs: baseline' .github/workflows/qemu.yml
          grep -Fq 'if: always()' .github/workflows/qemu.yml
          grep -Fq 'QEMU_SMOKE_PASS' files/qemu-smoke/etc/init.d/qemu-smoke
          grep -Fq '/proc/lrng_type' files/qemu-smoke/etc/init.d/qemu-smoke
          grep -Fq 'selftest_status' files/qemu-smoke/etc/init.d/qemu-smoke
```

- [ ] **Step 2: Commit, push, and run the deliberately failing check**

```bash
git add .github/workflows/validate.yml
git commit -m "test: define QEMU validation contract"
git push
gh workflow run validate.yml --repo MoozIiSP/BPI-R4-Firmware --ref codex/conservative-patch-qemu
```

Expected: the Ubuntu job fails on the first missing QEMU file. Record the run URL; do not reproduce it locally.

### Task 2: Share the generic patch manifest

**Files:**
- Create: `build/apply-generic-kernel-patches.sh`
- Modify: `build/02_prepare.sh:489-517`

- [ ] **Step 1: Create the helper**

```bash
#!/bin/bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 OPENWRT_ROOT ENABLE_LRNG(0|1)" >&2
  exit 2
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OPENWRT_ROOT="$1"
ENABLE_LRNG="$2"
case "$ENABLE_LRNG" in
  0|1) ;;
  *) echo "ERROR: ENABLE_LRNG must be 0 or 1" >&2; exit 2 ;;
esac

install_series() {
  local family="$1"
  local destination="$2"
  local source="$REPO_ROOT/patches/kernel/$family"
  local files=()
  shopt -s nullglob
  files=("$source"/*.patch)
  shopt -u nullglob
  if [ "${#files[@]}" -eq 0 ]; then
    echo "ERROR: no patches found for required family: $family" >&2
    exit 1
  fi
  mkdir -p "$OPENWRT_ROOT/$destination"
  cp "${files[@]}" "$OPENWRT_ROOT/$destination/"
  echo "[PATCHES] $family: ${#files[@]} patch(es) -> $destination"
}

install_series tcp target/linux/generic/backport-6.6
install_series fq target/linux/generic/backport-6.6
install_series bbr3 target/linux/generic/backport-6.6
install_series perf-cc target/linux/generic/hack-6.6
install_series arm target/linux/generic/hack-6.6
install_series wg target/linux/generic/hack-6.6
install_series btf target/linux/generic/hack-6.6
install_series sfe target/linux/generic/hack-6.6
install_series bcmfullcone target/linux/generic/hack-6.6

if [ "$ENABLE_LRNG" = "1" ]; then
  install_series lrng target/linux/generic/hack-6.6
  cat >> "$OPENWRT_ROOT/target/linux/generic/config-6.6" <<'LRNG'
# CONFIG_RANDOM_DEFAULT_IMPL is not set
CONFIG_LRNG=y
CONFIG_LRNG_DEV_IF=y
# CONFIG_LRNG_IRQ is not set
CONFIG_LRNG_JENT=y
CONFIG_LRNG_CPU=y
# CONFIG_LRNG_SCHED is not set
CONFIG_LRNG_SELFTEST=y
# CONFIG_LRNG_SELFTEST_PANIC is not set
# CONFIG_LRNG_AIS2031_NTG1_SEEDING_STRATEGY is not set
LRNG
else
  echo "[PATCHES] LRNG disabled"
fi
```

- [ ] **Step 2: Replace the TCP-through-bcmfullcone copy block in `build/02_prepare.sh`**

```bash
  bash ../build/apply-generic-kernel-patches.sh \
    "$PWD" \
    "${BPI_R4_ENABLE_LRNG:-0}"
```

Leave the three downloaded pending patches and the sysctl line unchanged.

- [ ] **Step 3: Commit and run remote validation**

```bash
git add build/apply-generic-kernel-patches.sh build/02_prepare.sh
git commit -m "refactor: share generic kernel patch selection"
git push
gh workflow run validate.yml --repo MoozIiSP/BPI-R4-Firmware --ref codex/conservative-patch-qemu
```

Expected: Bash syntax passes remotely; the contract fails only for QEMU files not yet created.

### Task 3: Add guest-side assertions

**Files:**
- Create: `files/qemu-smoke/etc/init.d/qemu-smoke`

- [ ] **Step 1: Create the init script**

```sh
#!/bin/sh /etc/rc.common
START=99

fail() {
  echo "QEMU_SMOKE_FAIL: $*"
  sync
  poweroff -f
  return 1
}

start() {
  echo "QEMU_SMOKE_BEGIN"
  if grep -qw 'bpi_lrng=1' /proc/cmdline; then mode=lrng; else mode=baseline; fi
  echo "QEMU_SMOKE_MODE=$mode"

  test -r /proc/sys/kernel/random/entropy_avail || fail "entropy_avail missing" || return 1
  echo "QEMU_ENTROPY_AVAIL=$(cat /proc/sys/kernel/random/entropy_avail)"
  dd if=/dev/urandom of=/tmp/urandom.bin bs=32 count=1 2>/dev/null || fail "urandom read failed" || return 1
  test "$(wc -c < /tmp/urandom.bin)" -eq 32 || fail "urandom short read" || return 1
  timeout 20 dd if=/dev/random of=/tmp/random.bin bs=32 count=1 2>/dev/null || fail "random read timed out" || return 1
  test "$(wc -c < /tmp/random.bin)" -eq 32 || fail "random short read" || return 1

  if [ "$mode" = lrng ]; then
    test -r /proc/lrng_type || fail "/proc/lrng_type missing" || return 1
    grep -q LRNG /proc/lrng_type || fail "LRNG identity missing" || return 1
    cat /proc/lrng_type
    selftest=/sys/module/lrng_selftest/parameters/selftest_status
    test -r "$selftest" || fail "selftest_status missing" || return 1
    test "$(cat "$selftest")" = 0 || fail "LRNG self-test failed" || return 1
    dmesg | grep -q 'LRNG self-tests passed' || fail "LRNG pass message missing" || return 1
    if dmesg | grep -Eiq 'LRNG.*(FAILED|failure)'; then fail "LRNG failure in dmesg" || return 1; fi
  else
    test ! -e /proc/lrng_type || fail "LRNG unexpectedly active" || return 1
  fi

  if dmesg | grep -Eq 'Kernel panic|not syncing:|Attempted to kill init'; then
    fail "fatal kernel message found" || return 1
  fi
  echo "QEMU_SMOKE_PASS mode=$mode"
  sync
  poweroff -f
}
```

- [ ] **Step 2: Commit without executing locally**

```bash
git add files/qemu-smoke/etc/init.d/qemu-smoke
git commit -m "test: add QEMU guest smoke assertions"
git push
```

### Task 4: Add the remote builder and host runner

**Files:**
- Create: `build/ci-qemu-build.sh`
- Create: `build/run-qemu-smoke.sh`

- [ ] **Step 1: Create `build/ci-qemu-build.sh`**

```bash
#!/bin/bash
set -euo pipefail
if [ "$#" -ne 1 ]; then echo "Usage: $0 ENABLE_LRNG(0|1)" >&2; exit 2; fi
ENABLE_LRNG="$1"
case "$ENABLE_LRNG" in 0) MODE=baseline ;; 1) MODE=lrng ;; *) exit 2 ;; esac

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OPENWRT_ROOT="$REPO_ROOT/qemu-openwrt"
DOWNLOAD_CACHE="$REPO_ROOT/.cache/qemu-dl"
OUTPUT_DIR="$REPO_ROOT/artifacts/qemu-$MODE"

resolve_tag() {
  if [ -n "${OPENWRT_TAG:-}" ]; then echo "$OPENWRT_TAG"; return; fi
  git ls-remote --tags --refs https://github.com/openwrt/openwrt.git 'refs/tags/v24.10*' \
    | awk -F/ '{print $NF}' | sort -V | tail -n 1
}
OPENWRT_TAG="$(resolve_tag)"
test -n "$OPENWRT_TAG"
echo "[QEMU BUILD] OpenWrt=$OPENWRT_TAG mode=$MODE"

rm -rf "$OPENWRT_ROOT" "$OUTPUT_DIR"
mkdir -p "$DOWNLOAD_CACHE" "$OUTPUT_DIR"
git clone --depth 1 --branch "$OPENWRT_TAG" https://github.com/openwrt/openwrt.git "$OPENWRT_ROOT"
ln -s "$DOWNLOAD_CACHE" "$OPENWRT_ROOT/dl"
bash "$REPO_ROOT/build/apply-generic-kernel-patches.sh" "$OPENWRT_ROOT" "$ENABLE_LRNG"
mkdir -p "$OPENWRT_ROOT/files"
cp -a "$REPO_ROOT/files/qemu-smoke/." "$OPENWRT_ROOT/files/"

cat > "$OPENWRT_ROOT/.config" <<'CONFIG'
CONFIG_TARGET_armsvirt=y
CONFIG_TARGET_armsvirt_64=y
CONFIG_TARGET_armsvirt_64_DEVICE_generic=y
CONFIG_TARGET_ROOTFS_INITRAMFS=y
CONFIG_TARGET_ROOTFS_SQUASHFS=n
CONFIG_PACKAGE_busybox=y
CONFIG_KERNEL_HW_RANDOM=y
CONFIG_KERNEL_HW_RANDOM_VIRTIO=y
CONFIG_LINUX_6_6=y
CONFIG

cd "$OPENWRT_ROOT"
make defconfig
make download -j"$(nproc)"
make -j"$(nproc)"
images=(bin/targets/armsvirt/64/*Image-initramfs*)
test "${#images[@]}" -eq 1
test -s "${images[0]}"
cp "${images[0]}" "$OUTPUT_DIR/Image-initramfs"
cp .config "$OUTPUT_DIR/openwrt.config"
cp target/linux/generic/config-6.6 "$OUTPUT_DIR/kernel-generic.config"
printf '%s\n' "$OPENWRT_TAG" > "$OUTPUT_DIR/openwrt-tag.txt"
if [ "$ENABLE_LRNG" = 1 ]; then
  grep -qx 'CONFIG_LRNG=y' "$OUTPUT_DIR/kernel-generic.config"
  test "$(find "$REPO_ROOT/patches/kernel/lrng" -maxdepth 1 -type f -name '*.patch' | wc -l)" -eq 27
else
  ! grep -qx 'CONFIG_LRNG=y' "$OUTPUT_DIR/kernel-generic.config"
fi
```

- [ ] **Step 2: Create `build/run-qemu-smoke.sh`**

```bash
#!/bin/bash
set -euo pipefail
if [ "$#" -ne 1 ]; then echo "Usage: $0 baseline|lrng" >&2; exit 2; fi
MODE="$1"
case "$MODE" in baseline) LRNG_FLAG=0 ;; lrng) LRNG_FLAG=1 ;; *) exit 2 ;; esac
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="$REPO_ROOT/artifacts/qemu-$MODE"
IMAGE="$OUTPUT_DIR/Image-initramfs"
LOG="$OUTPUT_DIR/serial.log"
test -s "$IMAGE"

set +e
timeout --signal=TERM --kill-after=15s 180s \
  qemu-system-aarch64 -machine virt,gic-version=3 -cpu cortex-a53 -smp 2 -m 1024 \
  -nographic -no-reboot -device virtio-rng-pci -kernel "$IMAGE" \
  -append "console=ttyAMA0 rdinit=/sbin/init bpi_lrng=$LRNG_FLAG" 2>&1 | tee "$LOG"
qemu_status="${PIPESTATUS[0]}"
set -e
test "$qemu_status" -eq 0
grep -Fq "QEMU_SMOKE_MODE=$MODE" "$LOG"
grep -Fq "QEMU_SMOKE_PASS mode=$MODE" "$LOG"
! grep -Fq 'QEMU_SMOKE_FAIL:' "$LOG"
! grep -Eq 'Kernel panic|not syncing:|Attempted to kill init' "$LOG"
```

- [ ] **Step 3: Commit and validate syntax remotely**

```bash
git add build/ci-qemu-build.sh build/run-qemu-smoke.sh
git commit -m "ci: add armsvirt build and QEMU smoke runners"
git push
gh workflow run validate.yml --repo MoozIiSP/BPI-R4-Firmware --ref codex/conservative-patch-qemu
```

Expected: remote Bash syntax passes; contract remains red only for the missing workflow.

### Task 5: Add the baseline-first workflow

**Files:**
- Create: `.github/workflows/qemu.yml`

- [ ] **Step 1: Create the workflow**

```yaml
name: QEMU ARM64 Smoke
run-name: QEMU ARM64 Smoke · ${{ inputs.enable_lrng && 'baseline + LRNG' || 'baseline' }} · ${{ github.ref_name }}

on:
  workflow_dispatch:
    inputs:
      enable_lrng:
        description: "Run LRNG only after baseline succeeds"
        required: true
        type: boolean
        default: false

permissions:
  contents: read

jobs:
  baseline:
    runs-on: ubuntu-24.04
    timeout-minutes: 240
    steps:
      - uses: actions/checkout@v4
      - uses: actions/cache@v4
        with:
          path: .cache/qemu-dl
          key: ${{ runner.os }}-qemu-dl-${{ hashFiles('build/*.sh', 'patches/kernel/**/*.patch') }}
          restore-keys: ${{ runner.os }}-qemu-dl-
      - name: Install dependencies
        run: |
          bash build/ci-install-deps.sh
          sudo apt-get install -y -qq --no-install-recommends qemu-system-arm
      - name: Build baseline
        run: bash build/ci-qemu-build.sh 0
      - name: Boot baseline
        run: bash build/run-qemu-smoke.sh baseline
      - name: Upload baseline evidence
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: qemu-arm64-baseline
          path: artifacts/qemu-baseline/
          if-no-files-found: warn

  lrng:
    needs: baseline
    if: ${{ inputs.enable_lrng }}
    runs-on: ubuntu-24.04
    timeout-minutes: 240
    steps:
      - uses: actions/checkout@v4
      - uses: actions/cache@v4
        with:
          path: .cache/qemu-dl
          key: ${{ runner.os }}-qemu-dl-${{ hashFiles('build/*.sh', 'patches/kernel/**/*.patch') }}
          restore-keys: ${{ runner.os }}-qemu-dl-
      - name: Install dependencies
        run: |
          bash build/ci-install-deps.sh
          sudo apt-get install -y -qq --no-install-recommends qemu-system-arm
      - name: Build LRNG
        run: bash build/ci-qemu-build.sh 1
      - name: Boot LRNG
        run: bash build/run-qemu-smoke.sh lrng
      - name: Upload LRNG evidence
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: qemu-arm64-lrng
          path: artifacts/qemu-lrng/
          if-no-files-found: warn
```

- [ ] **Step 2: Commit, push, and make the contract green**

```bash
git add .github/workflows/qemu.yml
git commit -m "ci: add baseline-first ARM64 QEMU smoke workflow"
git push
gh workflow run validate.yml --repo MoozIiSP/BPI-R4-Firmware --ref codex/conservative-patch-qemu
QEMU_VALIDATE_RUN_ID="$(gh run list --repo MoozIiSP/BPI-R4-Firmware --workflow validate.yml \
  --branch codex/conservative-patch-qemu --event workflow_dispatch --limit 1 \
  --json databaseId --jq '.[0].databaseId')"
gh run watch "$QEMU_VALIDATE_RUN_ID" --repo MoozIiSP/BPI-R4-Firmware --exit-status
```

Expected: all remote Validate jobs pass. This proves structure and syntax, not boot behavior.

### Task 6: Run baseline, then ordered LRNG QEMU

**Files:**
- No source changes unless GitHub logs provide a specific failure.

- [ ] **Step 1: Dispatch baseline-only**

```bash
gh workflow run qemu.yml --repo MoozIiSP/BPI-R4-Firmware \
  --ref codex/conservative-patch-qemu -f enable_lrng=false
QEMU_BASELINE_RUN_ID="$(gh run list --repo MoozIiSP/BPI-R4-Firmware --workflow qemu.yml \
  --branch codex/conservative-patch-qemu --event workflow_dispatch --limit 1 \
  --json databaseId --jq '.[0].databaseId')"
gh run watch "$QEMU_BASELINE_RUN_ID" --repo MoozIiSP/BPI-R4-Firmware --exit-status
```

Expected: `QEMU_SMOKE_PASS mode=baseline` and a non-empty `qemu-arm64-baseline` artifact.

- [ ] **Step 2: Dispatch baseline plus LRNG**

```bash
gh workflow run qemu.yml --repo MoozIiSP/BPI-R4-Firmware \
  --ref codex/conservative-patch-qemu -f enable_lrng=true
QEMU_LRNG_RUN_ID="$(gh run list --repo MoozIiSP/BPI-R4-Firmware --workflow qemu.yml \
  --branch codex/conservative-patch-qemu --event workflow_dispatch --limit 1 \
  --json databaseId --jq '.[0].databaseId')"
gh run watch "$QEMU_LRNG_RUN_ID" --repo MoozIiSP/BPI-R4-Firmware --exit-status
gh run view "$QEMU_LRNG_RUN_ID" --repo MoozIiSP/BPI-R4-Firmware --json url,headSha,conclusion,jobs
gh api "repos/MoozIiSP/BPI-R4-Firmware/actions/runs/$QEMU_LRNG_RUN_ID/artifacts" \
  --jq '.artifacts[] | [.name, .expired, .size_in_bytes] | @tsv'
```

Expected: baseline completes before LRNG; LRNG log shows `/proc/lrng_type` content, `LRNG self-tests passed`, and `QEMU_SMOKE_PASS mode=lrng`. Both artifacts are non-empty. On failure, inspect full GitHub logs and uploaded serial evidence; never run QEMU locally.

### Task 7: Build a separately named optional BPI-R4 LRNG image

**Files:**
- Modify: `.github/workflows/build.yml`
- Modify: `build/ci-build.sh:4-24,136-157`

- [ ] **Step 1: Add the workflow input and environment**

Add after `mtk_feed_release`:

```yaml
      enable_lrng:
        description: "Apply the optional 27-patch LRNG series"
        required: true
        type: boolean
        default: false
```

Add to job `env`:

```yaml
      BPI_R4_ENABLE_LRNG: ${{ inputs.enable_lrng && '1' || '0' }}
      BUNDLE_SUFFIX: ${{ inputs.enable_lrng && '-lrng' || '' }}
```

Use this verification path:

```bash
bundle="artifacts/bpi-r4-${BUILD_VARIANT}-${BUILD_MEDIA}${BUNDLE_SUFFIX}.zip"
```

Use these upload fields:

```yaml
          name: bpi-r4-${{ env.BUILD_VARIANT }}-${{ env.BUILD_MEDIA }}${{ env.BUNDLE_SUFFIX }}
          path: |
            artifacts/bpi-r4-${{ env.BUILD_VARIANT }}-${{ env.BUILD_MEDIA }}${{ env.BUNDLE_SUFFIX }}.zip
            artifacts/bpi-r4-${{ env.BUILD_VARIANT }}-${{ env.BUILD_MEDIA }}${{ env.BUNDLE_SUFFIX }}.zip.sha256sum
```

- [ ] **Step 2: Restrict and use the suffix in `ci-build.sh`**

Document `BUNDLE_SUFFIX empty|-lrng`, then initialize it:

```bash
BUNDLE_SUFFIX="${BUNDLE_SUFFIX:-}"
case "$BUNDLE_SUFFIX" in
  ''|-lrng) ;;
  *) echo "[CI] ERROR: BUNDLE_SUFFIX must be empty or -lrng" >&2; exit 1 ;;
esac
```

Change the bundle name to:

```bash
local bundle_name="bpi-r4-${BUILD_VARIANT}-${BUILD_MEDIA}${BUNDLE_SUFFIX}"
```

- [ ] **Step 3: Commit and validate remotely**

```bash
git add .github/workflows/build.yml build/ci-build.sh
git commit -m "ci: add optional BPI-R4 LRNG image build"
git push
gh workflow run validate.yml --repo MoozIiSP/BPI-R4-Firmware --ref codex/conservative-patch-qemu
```

- [ ] **Step 4: Reconfirm default, then build LRNG**

```bash
gh workflow run build.yml --repo MoozIiSP/BPI-R4-Firmware \
  --ref codex/conservative-patch-qemu -f variant=full -f media=sd \
  -f enable_mtk_feed=true -f mtk_feed_release=24.10 -f enable_lrng=false

gh workflow run build.yml --repo MoozIiSP/BPI-R4-Firmware \
  --ref codex/conservative-patch-qemu -f variant=full -f media=sd \
  -f enable_mtk_feed=true -f mtk_feed_release=24.10 -f enable_lrng=true
```

Expected: default artifact remains `bpi-r4-full-sd`; optional artifact is `bpi-r4-full-sd-lrng`. Both pass the on-runner ZIP/SHA256 gate. These builds authorize later sequential SD testing only, never eMMC or SPI-NAND flashing.

## Completion evidence and stop conditions

The handoff must list the run URL, head SHA, conclusion, artifact name, and non-zero artifact size for: Gate 1 native baseline; baseline-only QEMU; ordered baseline-plus-LRNG QEMU; reconfirmed default native build; optional LRNG native build.

Stop on the first substantive GitHub error. Do not add `|| true` to patch application, smoke assertions, self-tests, timeouts, or artifact checks. QEMU timings must not decide LRNG performance. The final default/optional decision remains blocked on three sequential SD-card runs per mode on the one physical BPI-R4.
