#!/usr/bin/env bash
# prepare.sh - build a VMS-ready zstd source tree in staging/<name>-<version>/
#
#   1. fetch + verify the upstream tarball
#   2. extract it, apply patches/series, lay overlay/ over the top
#   3. write the PCSI kit inputs
#
# zstd has no configure; tools/gen_sources.py lists the sources its makefiles
# use (whole directories) into vms/sources.mms.
# Nothing in staging/ is ever edited by hand: fix things in patches/ or overlay/.
set -euo pipefail

top=$(cd "$(dirname "$0")/.." && pwd)
. "$top/upstream.conf"
name=$UPSTREAM_NAME-$UPSTREAM_VERSION
tarball=$top/cache/$(basename "$UPSTREAM_URL")
stage=$top/staging/$name

step() { echo "prepare: $*"; }
die() { echo "prepare: error: $*" >&2; exit 1; }

"$top/tools/fetch.sh" >/dev/null

step "extracting $name"
rm -rf "$stage"; mkdir -p "$top/staging"
tar -xzf "$tarball" -C "$top/staging"
[ -d "$stage" ] || die "tarball did not unpack to $stage"

while read -r p; do
    case $p in ''|'#'*) continue ;; esac
    step "patch $p"
    patch -d "$stage" -p1 -s --no-backup-if-mismatch -F0 < "$top/patches/$p" ||
        die "patch $p does not apply cleanly"
done < "$top/patches/series"

(cd "$top/overlay" && find . -type f) | while read -r f; do
    [ -e "$stage/$f" ] && die "overlay/$f would replace an upstream file; use a patch"
    true
done
cp -a "$top/overlay/." "$stage/"

step "MMS source list"
python3 "$top/tools/gen_sources.py" "$stage" > "$stage/vms/sources.mms"
step "$(grep -c '^\$(LOBJ)' "$stage/vms/sources.mms") library objects, $(grep -c '^\$(OBJ)' "$stage/vms/sources.mms") CLI objects"

if [ -d "$stage/vms/kit" ]; then
step "PCSI kit inputs"
: "${KIT_PRODUCER:=ISSINOHO}"
# Three-part versions: the third part is the PCSI update and our VMS patch
# level the ECO, so $UPSTREAM_VERSION-vms$VMS_PATCH_LEVEL is V<major>.<minor>-<update>E<level>.
IFS=. read -r major minor update _ <<< "$UPSTREAM_VERSION"
pcsiversion="V$major.$minor-${update:-0}E$VMS_PATCH_LEVEL"
kitversion="$UPSTREAM_VERSION-vms$VMS_PATCH_LEVEL"
kit=$stage/vms/kit
subst() {
    sed -e "s/@PRODUCER@/$KIT_PRODUCER/g" -e "s/@BASE@/$1/g" \
        -e "s/@PCSIVERSION@/$pcsiversion/g" -e "s/@VERSION@/$UPSTREAM_VERSION/g" \
        -e "s/@KITVERSION@/$kitversion/g" -e "s/@ARCH@/$2/g"
}
# The headers the kit installs, as PCSI file lines.
includes=$( printf "%s\n" ZSTD.H ZSTD_ERRORS.H ZDICT.H | sed 's|.*|    file [ZSTD.INCLUDE]&;|; s|;$| ;|')
for base in I64VMS X86VMS; do
    subst $base "" < "$kit/zstd.pcsi\$desc_template" |
        awk -v d="$includes" '{ if ($0 == "@INCLUDES@") print d; else print }' > "$kit/ZSTD-$base.PCSI\$DESC"
    subst $base "" < "$kit/zstd.pcsi\$text_template" > "$kit/ZSTD-$base.PCSI\$TEXT"
done
rm -f "$kit/zstd.pcsi\$desc_template" "$kit/zstd.pcsi\$text_template"
mv "$kit/zstd\$startup.com" "$kit/ZSTD\$STARTUP.COM"
mv "$kit/zstd\$setup.com" "$kit/ZSTD\$SETUP.COM"
subst "" "IA64 and x86-64" < "$kit/readme.vms" > "$kit/README.VMS"; rm -f "$kit/readme.vms"
mkdir -p "$kit/doc"
cp "$stage/LICENSE" "$kit/doc/LICENSE."
cp "$stage/COPYING" "$kit/doc/COPYING."
cp "$stage/CHANGELOG" "$kit/doc/CHANGELOG."
cp "$stage/programs/zstd.1" "$kit/doc/ZSTD.1"
# The manual page's source is markdown, readable as it is.
cp "$stage/programs/zstd.1.md" "$kit/doc/ZSTD.TXT"
printf 'KIT_PRODUCER=%s\nPCSI_VERSION=%s\nKIT_VERSION=%s\n' "$KIT_PRODUCER" "$pcsiversion" \
    "$kitversion" > "$kit/kit.env"
fi

step "staged $stage"
