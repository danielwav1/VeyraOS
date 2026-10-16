#!/usr/bin/env bash
set -Eeuo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
VERSION=$(tr -d '[:space:]' < "$ROOT/VERSION")
SUITE=trixie
ARCH=amd64

WORK=${VEYRA_WORK_DIR:-$ROOT/build/work}
OUT=${VEYRA_OUT_DIR:-$ROOT/out}
MIN_FREE_GB=${VEYRA_MIN_FREE_GB:-20}
LOCALE=${VEYRA_LOCALE:-en_US.UTF-8}
KEYMAP=${VEYRA_KEYMAP:-us}
STAMP=$(date -u +%Y%m%d-%H%M%S)
ISO_NAME="VeyraOS-${VERSION}-live-${ARCH}.iso"
LOG="$OUT/build-${STAMP}.log"

DO_CHECK_ONLY=0
DO_CLEAN=0
DO_VERIFY=1

usage() {
    cat <<USAGE
Usage: ./build.sh [options]

Builds the VeyraOS ${VERSION} live ISO with Debian live-build.

  --check       run the preflight checks only, build nothing
  --clean       delete the work directory (including the package cache) and exit
  --no-verify   skip verify-iso.sh after the build
  -h, --help    this text

Environment:
  VEYRA_WORK_DIR     work directory      (default: build/work)
  VEYRA_OUT_DIR      output directory    (default: out)
  VEYRA_MIN_FREE_GB  required free space (default: 20)
  VEYRA_LOCALE       default locale      (default: en_US.UTF-8)
  VEYRA_KEYMAP       keyboard layout     (default: us)
  VEYRA_MIRROR       alternative Debian mirror URL
USAGE
}

msg()  { printf '\033[1;31m==>\033[0m %s\n' "$*"; }
note() { printf '    %s\n' "$*"; }
die()  { printf 'build.sh: %s\n' "$1" >&2; exit "${2:-1}"; }

as_root() {
    if (( EUID == 0 )); then
        "$@"
    else
        sudo "$@"
    fi
}

on_error() {
    local code=$? line=$1
    printf 'build.sh: failed at line %s (exit %s)\n' "$line" "$code" >&2
    [[ -f $LOG ]] && printf 'build.sh: log: %s\n' "$LOG" >&2
    exit "$code"
}
trap 'on_error $LINENO' ERR

LB_ARGS=(
    --distribution "$SUITE"
    --architecture "$ARCH"
    --binary-image iso-hybrid
    --debian-installer none
    --archive-areas "main non-free-firmware"
    --apt-recommends false
    --linux-flavours "$ARCH"
    --memtest none
    --checksums sha256
    --security true
    --updates true
    --iso-application "VeyraOS"
    --iso-publisher "VeyraOS Project; https://veyraos.is-a.dev"
    --iso-volume "VEYRAOS_${VERSION//./_}"
    --image-name "veyraos-${VERSION}-live"
    --bootappend-live "boot=live components quiet live-config.username=veyra live-config.hostname=veyraos live-config.locales=${LOCALE} live-config.keyboard-layouts=${KEYMAP} live-config.user-default-groups=audio,cdrom,dip,floppy,video,plugdev,netdev,scanner,bluetooth,lpadmin,sudo,adm,systemd-journal modprobe.blacklist=pnd2_edac"
)

if [[ -n ${VEYRA_MIRROR:-} ]]; then
    LB_ARGS+=(--mirror-bootstrap "$VEYRA_MIRROR" --mirror-chroot "$VEYRA_MIRROR" --mirror-binary "$VEYRA_MIRROR")
fi

check_host() {
    msg "Checking build host"
    [[ $(uname -s) == Linux ]] || die "a Linux build host is required" 3
    [[ $(uname -m) == x86_64 ]] || die "an x86_64 build host is required (this one is $(uname -m))" 3
    [[ -r /etc/os-release ]] || die "cannot read /etc/os-release" 3

    local id version_id
    id=$(. /etc/os-release && echo "${ID:-unknown}")
    version_id=$(. /etc/os-release && echo "${VERSION_ID:-0}")

    case $id in
        debian)
            (( ${version_id%%.*} >= 12 )) || die "Debian 12 or newer is required (found $version_id)" 3
            ;;
        *)
            if [[ ${VEYRA_ALLOW_UNSUPPORTED:-0} != 1 ]]; then
                die "host '$id' is not supported, use Debian 12/13 (or a Debian container). Set VEYRA_ALLOW_UNSUPPORTED=1 to try anyway." 3
            fi
            note "warning: unsupported host '$id', continuing because VEYRA_ALLOW_UNSUPPORTED=1"
            ;;
    esac
    note "host: $id $version_id"

    local missing=() tool
    for tool in lb debootstrap xorriso mksquashfs python3 file sha256sum install; do
        command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
    done
    if (( ${#missing[@]} )); then
        printf 'build.sh: missing tools: %s\n' "${missing[*]}" >&2
        printf 'Install them with:\n  sudo apt install live-build debootstrap squashfs-tools xorriso python3 file mtools dosfstools\n' >&2
        exit 3
    fi

    if [[ ! -e /usr/share/debootstrap/scripts/$SUITE ]]; then
        die "debootstrap on this host has no script for '$SUITE'; install a newer debootstrap (bookworm-backports on Debian 12)" 3
    fi
    note "debootstrap knows '$SUITE'"

    if (( EUID != 0 )) && ! command -v sudo >/dev/null 2>&1; then
        die "root privileges are needed for lb; install sudo or run as root" 3
    fi
}

check_lb_options() {
    msg "Checking live-build options"
    local help opt bad=0
    help=$(lb config --help 2>&1) || die "'lb config --help' failed" 3
    for opt in "${LB_ARGS[@]}"; do
        [[ $opt == --* ]] || continue
        if ! grep -qF -- "$opt" <<< "$help"; then
            printf 'build.sh: this live-build does not know %s\n' "$opt" >&2
            bad=1
        fi
    done
    (( bad == 0 )) || die "installed live-build is incompatible, see docs/BUILD.md" 3
    note "live-build: $(dpkg-query -W -f='${Version}' live-build 2>/dev/null || echo unknown)"
}

check_space() {
    msg "Checking free disk space"
    local probe=$WORK
    until [[ -d $probe ]]; do probe=$(dirname "$probe"); done
    local free
    free=$(df -BG --output=avail "$probe" | tail -n 1 | tr -dc '0-9')
    note "free in $probe: ${free} GB (need ${MIN_FREE_GB} GB)"
    (( free >= MIN_FREE_GB )) || die "not enough free space: ${free} GB available, ${MIN_FREE_GB} GB required" 1
}

source_date_epoch() {
    if git -C "$ROOT" rev-parse HEAD >/dev/null 2>&1; then
        git -C "$ROOT" log -1 --format=%ct
    else
        stat -c %Y "$ROOT/VERSION"
    fi
}

clean_work() {
    [[ -d $WORK ]] || return 0
    [[ -f $WORK/.veyra-work ]] || die "$WORK was not created by build.sh, refusing to delete it" 1
    as_root find "$WORK" -mindepth 1 -maxdepth 1 ! -name cache ! -name .veyra-work -exec rm -rf {} +
}

put() {
    install -D -m "$3" "$1" "$2"
}

put_tree() {
    local src=$1 dest=$2
    mkdir -p "$dest"
    cp -a "$src/." "$dest/"
}

stage() {
    msg "Staging configuration"
    local inc=$WORK/config/includes.chroot
    local build_date
    build_date=$(date -u +%Y-%m-%d)

    mkdir -p "$WORK"
    touch "$WORK/.veyra-work"
    clean_work
    mkdir -p "$WORK/config" "$inc"

    cp -a "$ROOT/live/config/." "$WORK/config/"

    put "$ROOT/scripts/veyra" "$inc/usr/local/bin/veyra" 755
    put "$ROOT/scripts/configure-live.sh" "$WORK/config/hooks/live/0100-veyra-configure.hook.chroot" 755

    sed "s/@BUILD_DATE@/$build_date/" "$ROOT/assets/branding/veyra-release" > "$WORK/veyra-release.tmp"
    put "$WORK/veyra-release.tmp" "$inc/etc/veyra-release" 644
    rm -f "$WORK/veyra-release.tmp"
    put "$ROOT/assets/branding/os-release" "$inc/usr/lib/os-release" 644
    put "$ROOT/assets/branding/issue" "$inc/etc/issue" 644
    put "$ROOT/assets/branding/issue.net" "$inc/etc/issue.net" 644

    local logo=$ROOT/assets/logo
    put "$logo/veyra-logo.svg" "$inc/usr/share/icons/hicolor/scalable/apps/veyra-logo.svg" 644
    put "$logo/veyra-logo-256.png" "$inc/usr/share/icons/hicolor/256x256/apps/veyra-logo.png" 644
    put "$logo/veyra-logo-48.png" "$inc/usr/share/icons/hicolor/48x48/apps/veyra-logo.png" 644
    local f
    for f in "$logo"/*; do
        put "$f" "$inc/usr/share/veyra/logo/$(basename "$f")" 644
    done
    put "$ROOT/assets/wallpaper/veyra-default.png" "$inc/usr/share/backgrounds/veyra/veyra-default.png" 644
    put "$ROOT/assets/wallpaper/veyra-default.svg" "$inc/usr/share/backgrounds/veyra/veyra-default.svg" 644

    put_tree "$ROOT/desktop/xfce/xdg" "$inc/etc/xdg"
    put_tree "$ROOT/desktop/xfce/skel" "$inc/etc/skel"
    put "$ROOT/desktop/shell/skel-bashrc" "$inc/etc/skel/.bashrc" 644
    put "$ROOT/desktop/shell/veyra.bashrc" "$inc/usr/share/veyra/shell/veyra.bashrc" 644
    put "$ROOT/desktop/lightdm/50-veyra.conf" "$inc/etc/lightdm/lightdm.conf.d/50-veyra.conf" 644
    put "$ROOT/desktop/systemd/veyra-password.service" "$inc/etc/systemd/system/veyra-password.service" 644

    local variant
    for variant in Dark Light; do
        put_tree "$ROOT/desktop/themes/Veyra-$variant" "$inc/usr/share/themes/Veyra-$variant"
        python3 "$ROOT/scripts/gen-xfwm4.py" "${variant,,}" "$inc/usr/share/themes/Veyra-$variant/xfwm4"
    done
    for f in "$ROOT"/desktop/themes/profiles/*.theme; do
        put "$f" "$inc/usr/share/veyra/themes/$(basename "$f")" 644
    done

    put "$ROOT/README.md" "$inc/usr/share/doc/veyraos/README.md" 644
    put "$ROOT/LICENSE" "$inc/usr/share/doc/veyraos/LICENSE" 644
    put "$ROOT/docs/DEBIAN-COMPONENTS.md" "$inc/usr/share/doc/veyraos/DEBIAN-COMPONENTS.md" 644
    put "$ROOT/docs/LIVE-SESSION.md" "$inc/usr/share/doc/veyraos/LIVE-SESSION.md" 644
}

build_image() {
    local sde
    sde=$(source_date_epoch)
    msg "Configuring live-build (suite $SUITE, $ARCH)"
    ( cd "$WORK" && as_root env SOURCE_DATE_EPOCH="$sde" lb config "${LB_ARGS[@]}" ) 2>&1 | tee -a "$LOG"

    msg "Building the image, this takes a while"
    note "log: $LOG"
    ( cd "$WORK" && as_root env SOURCE_DATE_EPOCH="$sde" lb build ) 2>&1 | tee -a "$LOG"
}

collect() {
    msg "Collecting results"
    local iso
    iso=$(find "$WORK" -maxdepth 1 -name '*.iso' -print -quit)
    [[ -n $iso ]] || die "lb build finished but produced no .iso in $WORK" 1

    cp "$iso" "$OUT/$ISO_NAME"
    ( cd "$OUT" && sha256sum "$ISO_NAME" > "$ISO_NAME.sha256" )

    local extra
    while IFS= read -r extra; do
        cp "$extra" "$OUT/VeyraOS-${VERSION}-live-${ARCH}.${extra##*.}"
    done < <(find "$WORK" -maxdepth 1 \( -name '*.packages' -o -name '*.contents' \))

    as_root chown -R "$(id -u):$(id -g)" "$OUT" 2>/dev/null || true
}

verify() {
    (( DO_VERIFY )) || { note "verification skipped (--no-verify)"; return 0; }
    msg "Verifying the image"
    bash "$ROOT/verify-iso.sh" "$OUT/$ISO_NAME"
}

summary() {
    local size
    size=$(du -h "$OUT/$ISO_NAME" | cut -f1)
    msg "Build finished"
    note "image:    $OUT/$ISO_NAME ($size)"
    note "sha256:   $(cut -d' ' -f1 "$OUT/$ISO_NAME.sha256")"
    note "log:      $LOG"
    note "next:     boot it in a VM (docs/TESTING.md) before writing it to a USB stick"
}

main() {
    while (( $# )); do
        case $1 in
            --check)     DO_CHECK_ONLY=1 ;;
            --clean)     DO_CLEAN=1 ;;
            --no-verify) DO_VERIFY=0 ;;
            -h|--help)   usage; exit 0 ;;
            *)           usage >&2; die "unknown option: $1" 2 ;;
        esac
        shift
    done

    if (( DO_CLEAN )); then
        if [[ -d $WORK ]]; then
            [[ -f $WORK/.veyra-work ]] || die "$WORK was not created by build.sh, refusing to delete it" 1
            as_root rm -rf "$WORK"
            msg "Removed $WORK"
        else
            msg "Nothing to clean"
        fi
        exit 0
    fi

    check_host
    check_lb_options
    check_space
    if (( DO_CHECK_ONLY )); then
        msg "Preflight checks passed"
        exit 0
    fi

    mkdir -p "$OUT"
    stage
    build_image
    collect
    verify
    summary
}

main "$@"
