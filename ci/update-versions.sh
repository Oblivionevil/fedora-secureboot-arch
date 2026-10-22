#!/usr/bin/env bash
# Ermittelt die aktuellen *stabilen* Fedora-Pakete (Kernel, shim, GRUB) und
# schreibt sie als kernel.env und bootloader.env nach OUTDIR.
#
#   ci/update-versions.sh OUTDIR [PREVDIR]
#
# PREVDIR enthält optional die bisherigen env-Dateien; daraus wird der
# fortlaufende SERIAL für das Bootloader-Paket weitergezählt.
# Es wird nur ein Fedora-Release verwendet, dessen RPM-Schlüssel in keys/
# hinterlegt ist – ein neues Release erfordert also einen geprüften Commit.
set -euo pipefail

MIRROR=${FEDORA_MIRROR:-https://dl.fedoraproject.org/pub/fedora/linux}
OUT=${1:?Aufruf: $0 OUTDIR [PREVDIR]}
PREV=${2:-}
KEYDIR=${KEYDIR:-$(dirname "$(readlink -f "$0")")/../keys}

die() { echo "update-versions: $*" >&2; exit 1; }

# Alle RPM-Dateinamen einer Verzeichnisliste
listing() {
    curl -fsSL --retry 3 "$MIRROR/$1/" | grep -oE 'href="[^"/]+\.rpm"' | sed 's/^href="//; s/"$//'
}

# Neuestes Release mit hinterlegtem Schlüssel und vorhandenem Repository
release=
for key in $(printf '%s\n' "$KEYDIR"/RPM-GPG-KEY-fedora-*-primary | sort -V -r); do
    n=${key##*/RPM-GPG-KEY-fedora-}
    n=${n%-primary}
    if curl -fsIL --retry 2 "$MIRROR/releases/$n/Everything/x86_64/os/repodata/repomd.xml" >/dev/null; then
        release=$n
        break
    fi
done
[[ -n $release ]] || die "kein Fedora-Release mit hinterlegtem Schlüssel gefunden"

dirs=("updates/$release/Everything/x86_64/Packages" "releases/$release/Everything/x86_64/os/Packages")

# latest NAME BUCHSTABE -> "VERSION-RELEASE<TAB>VERZEICHNIS" der neuesten x86_64-RPM
latest() {
    local name=$1 letter=$2 d f vr
    for d in "${dirs[@]}"; do
        while read -r f; do
            [[ $f == "$name"-*.x86_64.rpm ]] || continue
            vr=${f#"$name"-}
            vr=${vr%.x86_64.rpm}
            # schließt z.B. kernel-modules-core-* bei der Suche nach kernel-modules aus
            [[ $vr =~ ^[0-9][^-]*-[^-]+$ ]] || continue
            printf '%s\t%s\n' "$vr" "$d/$letter"
        done < <(listing "$d/$letter" || true)
    done | sort -V -k1,1 | tail -n1
}

# --- Kernel -----------------------------------------------------------------
read -r kvr kdir < <(latest kernel-core k) || die "kernel-core nicht gefunden"
kfiles=$(listing "$kdir")
for p in modules-core modules modules-extra; do
    grep -qxF "kernel-$p-$kvr.x86_64.rpm" <<<"$kfiles" || die "kernel-$p-$kvr fehlt in $kdir"
done
kver=${kvr%-*}
krel=${kvr#*-}
[[ $kver =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "unerwartete Kernel-Version $kver"
[[ $krel =~ ^[0-9]+\.fc[0-9]+$ ]] || die "unerwartetes Kernel-Release $krel (kein stabiles Build?)"

# --- shim + GRUB ------------------------------------------------------------
read -r svr sdir < <(latest shim-x64 s) || die "shim-x64 nicht gefunden"
read -r gvr gdir < <(latest grub2-efi-x64 g) || die "grub2-efi-x64 nicht gefunden"

mkdir -p "$OUT"
cat >"$OUT/kernel.env" <<EOF
FEDORA_RELEASE=$release
KERNEL_VERSION=$kver
KERNEL_RELEASE=$krel
KERNEL_PATH=$kdir
EOF

boot_body=$(cat <<EOF
FEDORA_RELEASE=$release
SHIM_VERSION=${svr%-*}
SHIM_RELEASE=${svr#*-}
SHIM_PATH=$sdir
GRUB_VERSION=${gvr%-*}
GRUB_RELEASE=${gvr#*-}
GRUB_PATH=$gdir
EOF
)

serial=1
if [[ -n $PREV && -r $PREV/bootloader.env ]]; then
    prev_serial=$(sed -n 's/^SERIAL=//p' "$PREV/bootloader.env")
    prev_body=$(grep -v '^SERIAL=' "$PREV/bootloader.env")
    if [[ $prev_body == "$boot_body" ]]; then
        serial=$prev_serial
    else
        serial=$(( ${prev_serial:-0} + 1 ))
    fi
fi
printf '%s\nSERIAL=%s\n' "$boot_body" "$serial" >"$OUT/bootloader.env"

echo "Fedora $release: kernel $kvr, shim $svr, grub2 $gvr (serial $serial)"
