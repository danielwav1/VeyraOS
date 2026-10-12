# VeyraOS

A Debian-based live Linux with a red V, a dark XFCE desktop and its own command line tool, `veyra`. It boots from a USB stick and leaves your disks alone.

> **Experimental, version 0.3 (Live Edition).** The build system and configuration are written and partly tested. The ISO has not been built or booted yet, and no hardware has been tested. See [Status](#status).

[Website](https://veyraos.is-a.dev) · [Issues](https://github.com/danielwav1/VeyraOS/issues) · [Docs](docs/)

## Screenshots

> **Placeholders.** No screenshots exist yet because no image has been booted.

| File | Shows |
|---|---|
| `docs/screenshots/desktop.png` | desktop with panel and wallpaper (placeholder) |
| `docs/screenshots/terminal.png` | terminal with the V banner (placeholder) |
| `docs/screenshots/veyra-info.png` | `veyra info` output (placeholder) |

## Features

- Bootable hybrid ISO for USB sticks and virtual machines (BIOS and UEFI)
- Live session only, **no installer** in 0.3
- XFCE with the Veyra-Dark (default) and Veyra-Light themes, red accent, own wallpaper, window decorations and panel layout
- Thunar, Mousepad, screenshot tool, task manager, NetworkManager, PipeWire audio, power management, Firefox ESR
- Terminal with a red V banner (once per window), `user@host:dir` prompt, exit-code marker, aliases
- The `veyra` CLI with 14 commands
- Own identity files: `/etc/os-release` (`ID=veyra`, `ID_LIKE=debian`), `/etc/veyra-release`, `/etc/issue`
- No telemetry, no hidden network services, no automatic changes to disks

VeyraOS is a Debian 13 ("trixie") derivative. The kernel, bootloader, package manager and nearly all software come from Debian unchanged. See [docs/DEBIAN-COMPONENTS.md](docs/DEBIAN-COMPONENTS.md).

## Requirements

### To run VeyraOS

| | |
|---|---|
| CPU | 64-bit x86 (amd64). ARM and 32-bit are not supported |
| RAM | 2 GB minimum, 4 GB or more recommended (the live system runs from RAM) |
| USB stick | 8 GB or more |
| Firmware | BIOS/legacy or UEFI. **Secure Boot must be off** |
| Wi-Fi, graphics | Firmware for common Intel, Realtek, Atheros Wi-Fi and AMD graphics is included. Other hardware may not work |

### To build the ISO

| | |
|---|---|
| Host | Debian 13 (recommended) or Debian 12 with a newer `debootstrap`, or a Debian container/VM. Ubuntu is not supported |
| Machine | x86_64, about 20 GB free disk space, internet access |
| Packages | `live-build debootstrap squashfs-tools xorriso python3 python3-pil python3-numpy file mtools dosfstools git` |
| Privileges | `sudo`. It is only used for the live-build steps |

No Debian machine? Use [GitHub Actions](#option-b-build-with-github-actions).

## Get the ISO

### Option A: build it yourself

```
sudo apt install live-build debootstrap squashfs-tools xorriso python3 python3-pil python3-numpy file mtools dosfstools git
git clone https://github.com/danielwav1/VeyraOS.git
cd VeyraOS
chmod +x build.sh verify-iso.sh scripts/*.sh scripts/veyra tests/*.sh
bash scripts/check-packages.sh
./build.sh --check
./build.sh
```

The result is in `out/`: `VeyraOS-0.3-live-amd64.iso`, a `.sha256` file and the build log. `build.sh` runs `verify-iso.sh` at the end. Options and details: [docs/BUILD.md](docs/BUILD.md).

### Option B: build with GitHub Actions

1. Fork or push this repository to your GitHub account.
2. Open **Actions**, pick **build-iso**, click **Run workflow**.
3. When it finishes, download the **veyraos-iso** artifact and unzip it.

The workflow builds inside a `debian:trixie` container. It has not been run yet, and GitHub runners have limited disk space.

## Flash it to a USB stick

Flashing erases the whole stick.

| From | Tool | Notes |
|---|---|---|
| Android | [EtchDroid](https://etchdroid.app) | Use **Flash raw image**, pick the `.iso` (not the zip). Needs a USB-OTG adapter |
| Windows | Rufus or balenaEtcher | In Rufus choose **DD Image mode** |
| Linux | `dd` | See below |

```
lsblk
sudo dd if=out/VeyraOS-0.3-live-amd64.iso of=/dev/sdX bs=4M status=progress conv=fsync
```

Replace `/dev/sdX` with your stick. Check it with `lsblk` first.

## Boot it

1. Plug the stick into the target PC and open its boot menu (usually F12, F10, Esc or F2).
2. Pick the USB entry. Turn Secure Boot off if the stick does not appear.
3. You land on the desktop as user `veyra`, logged in automatically.

Try a VM first if you can:

```
qemu-system-x86_64 -m 3072 -smp 2 -enable-kvm -cdrom out/VeyraOS-0.3-live-amd64.iso -boot d
```

Black screen? Press `e` on the boot entry and add `nomodeset` to the kernel line.

### What a live session means

- Nothing is installed and the stick is not written to. Every change is lost on shutdown.
- Internal disks are not touched. Mounting one asks for authentication.
- `sudo` works without a password. Persistence is not part of 0.3.

Details: [docs/LIVE-SESSION.md](docs/LIVE-SESSION.md).

## The `veyra` command

Run `veyra help` for the list. Options before the command: `-y/--yes` (answers yes in `update` and `clean`, never in `repair`) and `--no-color`.

| Command | What it does |
|---|---|
| `veyra help` | command overview |
| `veyra version [--short]` | version and edition |
| `veyra info` | system overview |
| `veyra sys` | kernel, CPU, memory, swap, uptime, root filesystem |
| `veyra checkup` | checks identity, memory, disk, services, desktop, dpkg, route, sudo |
| `veyra desktop` | desktop session, components, active themes |
| `veyra update` | refresh package lists, upgrade after confirmation |
| `veyra clean` | show and remove the APT cache and unused packages after confirmation |
| `veyra repair` | read-only diagnostics, then fixes after confirmation (interactive only) |
| `veyra logs [errors\|boot\|kernel\|unit NAME] [-n N]` | journal output |
| `veyra network [--offline]` | interfaces, gateway, DNS and HTTPS check |
| `veyra theme [list\|current\|set NAME]` | list and switch `veyra-dark` / `veyra-light` |
| `veyra about` | project information |
| `veyra report [-o FILE]` | local diagnostic report with hostname, user, paths, IPs, MACs and UUIDs masked. Nothing is sent anywhere |
| `veyra banner` | startup banner |

Exit codes: `0` ok, `1` failure, `2` usage error, `3` missing dependency. `veyra network` contacts `deb.debian.org` unless you pass `--offline`.

## Status

| Part | State |
|---|---|
| Build system | written, preflight failure paths exercised, **full build not run** |
| ISO image | **not built** |
| Live boot in a VM or on hardware | **not tested** |
| `veyra` CLI | implemented, non-interactive and failure paths tested on Ubuntu 24.04 |
| Automated tests | 141 passed, 0 failed, 1 skipped (no ISO to check) |
| Desktop config, themes, panel | written and XML-validated, never seen on a screen |

Run the tests with `bash tests/run.sh` (add `--vm` to boot a built ISO in QEMU). The manual checklist is in [docs/TESTING.md](docs/TESTING.md).

## Known limitations

- ISO and boot are untested, see [Status](#status)
- Secure Boot, ARM, installer and persistence are not supported
- The boot menu uses live-build's default look, there is no custom boot splash yet
- The GTK themes are a thin layer over Arc. GTK4/libadwaita apps keep their own look
- Package names are not yet checked against the Debian archive, run `scripts/check-packages.sh`
- English by default. For German: `VEYRA_LOCALE=de_DE.UTF-8 VEYRA_KEYMAP=de ./build.sh`
- Builds are not bit-for-bit reproducible

Problems? See [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) or open an issue with the output of `veyra report`.

## Project layout

```
build.sh  verify-iso.sh  VERSION
assets/       logo (svg, png, mono), wallpaper, branding files
desktop/      XFCE defaults, themes, shell rc, LightDM
live/config/  live-build package list
scripts/      veyra, configure-live.sh, gen-xfwm4.py, render-assets.py, check-packages.sh
docs/         build, testing, troubleshooting, live session, Debian components
tests/        run.sh and test files
.github/      ISO build workflow
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Please say what you actually tested. "Untested" is fine.

## License

MIT for the VeyraOS files, see [LICENSE](LICENSE). Debian packages in the image keep their own licenses.

## Credits

Created by **Daniel.veyra**. Built on Debian, the Linux kernel, XFCE, the Arc theme and Papirus icons.
