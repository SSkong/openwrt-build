# Conservative Kernel Patch Cleanup and QEMU Validation Design

## Objective

Restore a passing BPI-R4 `full / sd / MTK feed 24.10` build with the smallest evidence-backed patch cleanup, then validate the generic kernel patch stack and the currently disabled LRNG stack in an ARM64 QEMU guest before any real-device testing.

All builds, tests, QEMU boots, and validation commands run on GitHub Actions Linux runners. The local macOS host is used only for source inspection and editing.

## Current Evidence

- GitHub Actions run `31002771021` is the failing baseline for commit `2048293`.
- The previous successful build selected OpenWrt `v24.10.6` and Linux `6.6.127`.
- The failing build selected OpenWrt `v24.10.8` and Linux `6.6.144`.
- Linux `6.6.144` already contains `TCP_ACK_DEFERRED` and `tcp_backlog_ack_defer`.
- The local `630-04-v6.7-tcp-defer-regular-ACK-while-processing-socket-backlog.patch` attempts to add the same functionality and fails in five kernel files.
- `SAENE/luci-theme-design` no longer exists, and the cloned directory is not consumed elsewhere in the repository.
- The LRNG series contains 27 patches and is present in the repository but excluded from the validated default build unless `BPI_R4_ENABLE_LRNG=1`.

## Scope

### Included

1. Conservatively remove only patches proven redundant, upstreamed, obsolete, or unused on the current OpenWrt/Linux baseline.
2. Remove the unused clone of the deleted `SAENE/luci-theme-design` repository.
3. Re-run the existing BPI-R4 full SD build with the same MTK feed settings.
4. Add an ARM64 QEMU smoke workflow using an OpenWrt `armsvirt/64` initramfs image.
5. Exercise the same generic kernel patch selection in QEMU, first without LRNG and then with LRNG.
6. Preserve logs and QEMU images as workflow artifacts for inspection.
7. Defer the final LRNG default/optional decision until real BPI-R4 measurements are available.

### Excluded

- Emulating the MT7988 SoC or booting the BPI-R4 device image in QEMU.
- Validating MediaTek Wi-Fi, WED, HNAT, DTS, SFP, A/B storage, or the custom bootloader in QEMU.
- Broadly deleting BBR3, SFE, Fullcone, FQ, perf-cc, BTF, or other patch families without direct evidence.
- Running builds, tests, patch application checks, or QEMU on the local macOS host.
- Flashing eMMC or SPI-NAND during the later real-device performance comparison.

## Approaches Considered

### 1. Two-gate conservative cleanup and QEMU validation — selected

First restore the real BPI-R4 build by removing only confirmed redundant or dead inputs. After that build passes, introduce a separate QEMU workflow with an LRNG switch and validate the generic patch stack in two runs. This keeps each failure attributable to one change and protects the production build path.

### 2. Immediately re-enable LRNG in the BPI-R4 full build

This is faster in workflow count but mixes baseline repair with 27 invasive patches. A failure would not distinguish stale baseline patches from LRNG incompatibility, so this approach is rejected.

### 3. Remove most historical performance patches before rebuilding

This produces a cleaner upstream-oriented tree but exceeds the requested conservative scope and risks silently removing desired router features. It is rejected unless later evidence shows additional series are obsolete.

## Architecture

### Gate 1: BPI-R4 baseline repair

The existing `Build Firmware Image` workflow remains the authoritative device build. Patch cleanup is based on semantic evidence, not merely whether `patch(1)` accepts a hunk.

For the TCP backlog-ACK series:

1. Compare each patch's intended kernel behavior with Linux `6.6.144`.
2. Remove a patch only when the behavior already exists upstream or the patch is solely a prerequisite for behavior that now exists upstream.
3. Keep unrelated patch families unchanged.

The dead `luci-theme-design` clone is removed because the remote repository is gone and no build step consumes its checkout.

Gate 1 passes only when a fresh GitHub Actions run using these inputs succeeds:

- variant: `full`
- medium: `sd`
- MediaTek feed: enabled
- MediaTek feed release: `24.10`

The workflow must complete the build step, upload `bpi-r4-full-sd`, and publish both the ZIP bundle and its SHA256 file.

### Gate 2: QEMU baseline smoke image

A dedicated GitHub workflow builds an OpenWrt `armsvirt/64` initramfs from the same resolved OpenWrt release. It injects only generic kernel patches that are applicable to an ARM64 virtual machine; BPI-R4, MediaTek, bootloader, storage-layout, wireless-regdb, and package-overlay changes are excluded.

The workflow boots the initramfs with `qemu-system-aarch64` using the `virt` machine and captures the serial console. Guest interaction verifies:

- the kernel reaches userspace;
- no kernel panic or fatal init failure occurs;
- `/proc/sys/kernel/random/entropy_avail` is readable;
- random data can be read successfully;
- the guest shuts down under workflow control.

The QEMU kernel image and serial log are uploaded as artifacts even when the smoke assertion fails.

### Gate 3: LRNG QEMU smoke image

The same QEMU workflow exposes an explicit LRNG input or matrix dimension. When enabled, it applies the repository's 27 LRNG patches and required kernel configuration. The guest checks the baseline assertions plus:

- LRNG-specific kernel configuration is active;
- an LRNG identity/status interface is present when supplied by the selected series;
- dmesg contains LRNG initialization and no LRNG self-test failure;
- random reads complete without blocking or kernel warnings.

The baseline QEMU run must pass before the LRNG run is considered meaningful.

### Gate 4: Real-device performance decision

After both QEMU modes and both BPI-R4 images build successfully, the native and LRNG images are booted sequentially from SD card on the same BPI-R4. Each mode is measured at least three times for entropy readiness, boot timing, random-read throughput, and CPU cost. QEMU timing is not used for the performance decision.

LRNG becomes the full-build default only if it shows a repeatable benefit without boot, stability, or CPU regressions. Otherwise it remains an explicit optional build.

## Failure Handling

- Patch application failures are fatal and identify the exact patch; no new blanket `|| true` is introduced.
- QEMU has a bounded boot timeout and always uploads the captured serial log.
- A failed device build does not trigger LRNG enablement.
- A failed baseline QEMU run blocks LRNG interpretation.
- A failed LRNG run leaves the normal full build unchanged.
- No automatic source edits or retries attempt to hide a deterministic patch failure.

## Validation Strategy

The remote GitHub workflow is the test harness because local testing is prohibited for this task.

1. **Existing red evidence:** run `31002771021` fails while applying the obsolete TCP patch on Linux `6.6.144`.
2. **Gate 1 green:** the same BPI-R4 workflow inputs build and upload the expected bundle.
3. **Gate 2 green:** the non-LRNG armsvirt initramfs boots and passes guest assertions.
4. **Gate 3 green:** the LRNG armsvirt initramfs boots and passes LRNG-specific assertions.
5. **Device-build green:** a BPI-R4 LRNG image compiles successfully before any flash test.
6. **Hardware evidence:** sequential SD-card measurements decide whether LRNG is default or optional.

## Success Criteria

- The conservative cleanup is limited to items with recorded evidence.
- The normal BPI-R4 full SD build succeeds on GitHub Actions and publishes valid artifacts.
- The QEMU baseline image boots and completes automated smoke checks.
- The QEMU LRNG image boots and completes LRNG smoke checks.
- The normal full profile is not made dependent on LRNG before hardware measurements.
- No validation or test command is executed on the local macOS host.

