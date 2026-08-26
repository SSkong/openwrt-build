# BPI-R4 Firmware

OpenWrt 24.10 firmware for Banana Pi BPI-R4 (MT7988 / Filogic 880).

## Quick Start

```bash
git clone -b main https://github.com/MoozIiSP/BPI-R4-Firmware.git
cd BPI-R4-Firmware

# Build with Makefile
make full        # Full-featured router
make minimal     # Base + WiFi 7 + bootloader validation
make validate    # Run local checks
make clean       # Remove cloned source trees
```

## Directory Structure

```
├── build/                    # Build automation scripts
│   ├── 01_clone.sh           # Clone OpenWrt + deps (--variant full|minimal)
│   ├── 02_prepare.sh         # Apply patches, configure feeds (--variant full|minimal)
│   └── 03_target.sh          # Target-specific config
├── files/                    # Rootfs overlay (etc/ configuration)
├── seed/                     # OpenWrt .config seed files
│   ├── full.seed             # Full-featured router
│   ├── minimal.seed          # Base + WiFi 7 validation
│   ├── nand.seed             # SPI-NAND optimized
│   └── pro.seed              # BPI-R4-PRO variant
├── patches/                  # Kernel & package patches
│   ├── kernel/               # Kernel patches (bbr3, sfe, networking, etc.)
│   ├── packages/             # Package-level patches (firewall, miniupnpd)
│   └── gpt/                  # A/B partition layouts
├── tools/                    # Validation & analysis tools
├── tests/                    # Test suite
├── docs/                     # Documentation
│   ├── ci-release-flow.md    # GitHub Actions build/release flow
│   ├── mtk-feed-custom-bootloader-build.md
│   │                           # MTK feed + custom bootloader build notes
│   └── templates/            # Report & checklist templates
├── Makefile                  # Build entry point
└── .github/workflows/        # CI/CD pipelines
```

## Build Variants

| Seed | Use Case | Rootfs | Key Packages |
|------|----------|--------|-------------|
| `full` | Daily driver router | 4096MB | DAE, passwall, openclash, ZT, TS, all LuCI |
| `minimal` | MTK/bootloader validation | 512MB | WiFi 7 firmware, bootloader only |
| `nand` | SPI-NAND boot | 4096MB | Reduced package set |
| `pro` | BPI-R4-PRO hardware | 4096MB | Same as full, PRO device target |

## Features

- **OpenWrt 24.10** with Kernel 6.6 (version-locked)
- **Custom U-Boot** (Yuzhii0718/bl-mt798x-dhcpd) with DHCPD/WebUI
- **WiFi 7** (MT7996) with TX power unlock and region-free regdb
- **10G networking** with WED hardware offload, SFE, BBRv3
- **A/B partition** support for SD, eMMC, and SPI-NAND
- **Full LuCI** web interface with Chinese/English languages
- **Fullcone NAT**, Shortcut-FE, WireGuard, ZeroTier, Tailscale
- **DAE** (Destination Aware Engine) with BPF acceleration

## CI/CD

| Workflow | Trigger | Runner |
|----------|---------|--------|
| **Validate** | push/PR/manual | ubuntu-latest |
| **Build Firmware** | manual | ubuntu-24.04 |
| **Release Firmware** | tag `v*`/manual | ubuntu-24.04 |
| **Release Packages** | tag `packages-v*`/manual | ubuntu-24.04 |

See `docs/ci-release-flow.md` for the normalized build and release flow.

## License

GPL-2.0
