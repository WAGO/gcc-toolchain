# gcc-toolchain – gcc13.4-03.00.05

Yocto-generated cross toolchains for the PFC firmware SDK (x86_64 Linux host).
The installers are attached to the GitHub release `gcc-toolchain-gcc13.4-03.00.05`. This branch contains the matching package lists and license data.

| Target | Triplet | Installer |
|---|---|---|
| ARM 32 bit (Cortex-A8, hard-float, NEON) | `arm-poky-linux-gnueabi` | `ybp-glibc-x86_64-wago-toolchain-cortexa8hf-neon-wago-arm-toolchain-03.00.05-1-3686ba00f3.sh` |
| AArch64 | `aarch64-poky-linux` | `ybp-glibc-x86_64-wago-toolchain-aarch64-wago-aarch64-toolchain-03.00.05-1-3686ba00f3.sh` |

Components (both toolchains): GCC 13.4.0, Binutils 2.42, GDB 14.2, glibc 2.39, Linux headers 6.6.

## Installation

```bash
sha256sum -c --ignore-missing SHA256SUMS   # SHA256SUMS is part of the release
chmod +x <installer>.sh
./<installer>.sh -y -d /opt/toolchain       # any directory
. /opt/toolchain/environment-setup-cortexa8hf-neon-poky-linux-gnueabi
$CC hello.c -o hello
```

The environment script of the AArch64 toolchain is `environment-setup-aarch64-poky-linux`.

## Contents of this branch

- `manifests/`: installed packages (host and target) per toolchain
- `spdx/`: SPDX documents with license information per recipe (`NOASSERTION` where not determined)
- `SHA256SUMS`: checksums of all release assets

## Known limitation

The target sysroot has no per-language locale definitions (e.g. `de_DE`). Build systems that run `localedef` (such as PTXdist) must provide them, e.g. from `localedata/locales` of the glibc 2.39 sources.

## License

The files in this repository are under GPL-3.0, see [LICENSE](LICENSE). The toolchain installers contain open source software under their own licenses (among others GPL, LGPL, BSD, MIT, Apache-2.0); see `manifests/` and `spdx/`.

Earlier (Linaro based) toolchains: branches `release/2022.02`, `release/2022.08`, `release/2022.08-wago.1`.
