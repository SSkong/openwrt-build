#!/bin/bash
set -euo pipefail

# =============================================================================
# 01_clone.sh — Clone OpenWrt 24.10 source and dependencies
# =============================================================================
# Usage: Run from repository root: bash build/01_clone.sh [--variant VARIANT]
#
# Variants:
#   full      — Clone OpenWrt + bootloader + all third-party repos (default)
#   minimal   — Clone OpenWrt + bootloader only (cache-aware for CI)
# =============================================================================

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

# --- Argument parsing --------------------------------------------------------
VARIANT="full"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --variant|-v) VARIANT="$2"; shift 2 ;;
    --help|-h)
      echo "Usage: $0 [--variant full|minimal]"
      exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

# --- Helper ------------------------------------------------------------------
clone_repo() {
  local repo_url="$1" branch_name="$2" target_dir="$3"
  if [ -d "$target_dir/.git" ]; then
    echo "[CLONE] $target_dir already exists, skipping."
    return 0
  fi
  echo "[CLONE] Cloning $repo_url ($branch_name) → $target_dir"
  git clone -b "$branch_name" --depth 1 "$repo_url" "$target_dir"
}

# --- Resolve OpenWrt 24.10 release tag ---------------------------------------
resolve_openwrt_tag() {
  local tag
  if [ -n "${OPENWRT_TAG:-}" ]; then
    echo "$OPENWRT_TAG"
    return 0
  fi

  tag="$(git ls-remote --tags --refs https://github.com/openwrt/openwrt.git 'refs/tags/v24.10*' \
    | awk -F/ '{print $NF}' \
    | sort -V \
    | tail -n 1)"
  if [ -z "$tag" ]; then
    echo "[CLONE] ERROR: Could not resolve OpenWrt v24.10 tag" >&2
    exit 1
  fi
  echo "$tag"
}

OPENWRT_TAG="$(resolve_openwrt_tag)"
echo "[CLONE] Resolved OpenWrt release: $OPENWRT_TAG"

# --- Repository URLs ---------------------------------------------------------
OPENWRT_REPO="https://github.com/openwrt/openwrt.git"
BOOTLOADER_REPO="https://github.com/MoozIiSP/bl-mt798x-dhcpd.git"

# Third-party repos (full variant only)
LEDE_REPO="https://github.com/coolsnowwolf/lede.git"
LEDE_PKG_REPO="https://github.com/coolsnowwolf/packages.git"
OPENWRT_PKG_REPO="https://github.com/openwrt/packages.git"
OPENWRT_ADD_REPO="https://github.com/QiuSimons/OpenWrt-Add.git"
DOCKERMAN_REPO="https://github.com/lisaac/luci-app-dockerman"
DOCKER_LIB_REPO="https://github.com/lisaac/luci-lib-docker"

# --- Clone logic -------------------------------------------------------------
if [ "$VARIANT" = "minimal" ]; then
  # Minimal: cache-aware clone for CI
  if [ ! -d "openwrt/.git" ]; then
    echo "[CLONE] OpenWrt source missing or incomplete. Re-cloning..."

    # 1. Back up cached directories
    for dir in dl staging_dir build_dir; do
      if [ -d "openwrt/$dir" ]; then
        echo "[CLONE] Backing up openwrt/$dir → _saved_$dir"
        mv "openwrt/$dir" "./_saved_$dir"
      fi
    done

    # 2. Clean and clone
    rm -rf openwrt
    clone_repo "$OPENWRT_REPO" "$OPENWRT_TAG" openwrt &
    clone_repo "$OPENWRT_REPO" "openwrt-24.10" openwrt_snap &
    clone_repo "$BOOTLOADER_REPO" "master" bl-mt798x-dhcpd &
    wait

    # 3. Restore caches
    for dir in dl staging_dir build_dir; do
      if [ -d "./_saved_$dir" ]; then
        echo "[CLONE] Restoring _saved_$dir → openwrt/$dir"
        mv "./_saved_$dir" "openwrt/$dir"
      fi
    done
  else
    echo "[CLONE] OpenWrt source already present."
    clone_repo "$OPENWRT_REPO" "openwrt-24.10" openwrt_snap
    clone_repo "$BOOTLOADER_REPO" "master" bl-mt798x-dhcpd
  fi

  # Setup base package structure
  if [ -d "openwrt" ]; then
    find openwrt/package/* -maxdepth 0 \
      ! -name 'firmware' ! -name 'kernel' ! -name 'base-files' ! -name 'Makefile' \
      -exec rm -rf {} +
    if [ -d "openwrt_snap" ]; then
      rm -rf ./openwrt_snap/package/{firmware,kernel,base-files,Makefile}
      cp -rf ./openwrt_snap/package/* ./openwrt/package/
      cp -rf ./openwrt_snap/feeds.conf.default ./openwrt/feeds.conf.default
    fi
  fi

else
  # Full: clone everything
  if [ ! -d "openwrt/.git" ]; then
    for dir in dl staging_dir build_dir; do
      if [ -d "openwrt/$dir" ]; then
        echo "[CLONE] Backing up openwrt/$dir → _saved_$dir"
        mv "openwrt/$dir" "./_saved_$dir"
      fi
    done
    rm -rf openwrt
  fi

  clone_repo "$OPENWRT_REPO" "$OPENWRT_TAG" openwrt
  clone_repo "$OPENWRT_REPO" "openwrt-24.10" openwrt_snap
  clone_repo "$BOOTLOADER_REPO" "master" bl-mt798x-dhcpd

  for dir in dl staging_dir build_dir; do
    if [ -d "./_saved_$dir" ]; then
      echo "[CLONE] Restoring _saved_$dir → openwrt/$dir"
      mv "./_saved_$dir" "openwrt/$dir"
    fi
  done

  # Third-party repos
  clone_repo "$LEDE_REPO" "master" lede &
  clone_repo "$LEDE_PKG_REPO" "master" lede_pkg_ma &
  clone_repo "$OPENWRT_PKG_REPO" "master" openwrt_pkg_ma &
  clone_repo "$OPENWRT_ADD_REPO" "master" OpenWrt-Add &
  clone_repo "$DOCKERMAN_REPO" "master" dockerman &
  clone_repo "$DOCKER_LIB_REPO" "master" docker_lib &
  wait

  # Merge snap packages
  find openwrt/package/* -maxdepth 0 \
    ! -name 'firmware' ! -name 'kernel' ! -name 'base-files' ! -name 'Makefile' \
    -exec rm -rf {} +
  rm -rf ./openwrt_snap/package/{firmware,kernel,base-files,Makefile}
  cp -rf ./openwrt_snap/package/* ./openwrt/package/
  cp -rf ./openwrt_snap/feeds.conf.default ./openwrt/feeds.conf.default
fi

echo "[CLONE] Repositories cloned and prepared (variant: $VARIANT)."
