#!/bin/sh

set -eu

usage() {
    echo "usage: $0 [--apply BOBSBUDDY_VERSION HEARTHDB_VERSION]" >&2
    exit 2
}

APPLY=0
case "${1-}" in
    "")
        [ "$#" -eq 0 ] || usage
        ;;
    --apply)
        [ "$#" -eq 3 ] || usage
        APPLY=1
        BOBS_CONFIRMED_VERSION=$2
        HEARTHDB_CONFIRMED_VERSION=$3
        ;;
    *)
        usage
        ;;
esac

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(dirname "$SCRIPT_DIR")
BOBS_URL="https://libs.hearthsim.net/hdt/BobsBuddy.zip"
HEARTHDB_URL="https://libs.hearthsim.net/hdt/HearthDb.zip"
STAGING=$(mktemp -d)
trap 'rm -rf "$STAGING"' EXIT HUP INT TERM

/usr/bin/curl -fL --connect-timeout 20 -o "$STAGING/BobsBuddy.zip" "$BOBS_URL"
/usr/bin/curl -fL --connect-timeout 20 -o "$STAGING/HearthDb.zip" "$HEARTHDB_URL"
mkdir -p "$STAGING/bobsbuddy" "$STAGING/hearthdb"
unzip -q "$STAGING/BobsBuddy.zip" -d "$STAGING/bobsbuddy"
unzip -q "$STAGING/HearthDb.zip" -d "$STAGING/hearthdb"

for file in BobsBuddy.dll BobsBuddy.Common.dll; do
    if [ ! -f "$STAGING/bobsbuddy/$file" ]; then
        echo "error: downloaded BobsBuddy.zip is missing $file" >&2
        exit 1
    fi
done
for file in HearthDb.dll HearthDb.xml; do
    if [ ! -f "$STAGING/hearthdb/$file" ]; then
        echo "error: downloaded HearthDb.zip is missing $file" >&2
        exit 1
    fi
done

BOBS_VERSION=$(
    /usr/bin/strings "$STAGING/bobsbuddy/BobsBuddy.dll" |
        /usr/bin/sed -n 's#^/\([0-9][0-9.]*\)[+].*#\1#p' |
        /usr/bin/head -n 1
)
if [ -z "$BOBS_VERSION" ]; then
    echo "error: could not read the assembly version from downloaded BobsBuddy.dll" >&2
    exit 1
fi

# HearthDb has no anchored informational-version string like BobsBuddy. This
# assumes the assembly contains exactly one standalone x.y.z string.
HEARTHDB_VERSIONS=$(
    /usr/bin/strings "$STAGING/hearthdb/HearthDb.dll" |
        /usr/bin/sed -n '/^[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*$/p' |
        /usr/bin/sort -u
)
HEARTHDB_VERSION_COUNT=$(
    printf '%s\n' "$HEARTHDB_VERSIONS" |
        /usr/bin/sed '/^$/d' |
        /usr/bin/wc -l |
        /usr/bin/tr -d ' '
)
if [ "$HEARTHDB_VERSION_COUNT" -ne 1 ]; then
    echo "error: expected one standalone x.y.z string in downloaded HearthDb.dll, found $HEARTHDB_VERSION_COUNT" >&2
    [ -z "$HEARTHDB_VERSIONS" ] || printf '%s\n' "$HEARTHDB_VERSIONS" >&2
    exit 1
fi
HEARTHDB_VERSION=$HEARTHDB_VERSIONS

BOBS_CURRENT=$(cat "$REPO_ROOT/HSTracker/BobsBuddy-version.txt")
HEARTHDB_CURRENT=$(cat "$REPO_ROOT/HSTracker/HearthDb-version.txt")
printf 'BobsBuddy: %s -> %s\n' "$BOBS_CURRENT" "$BOBS_VERSION"
printf 'HearthDb:  %s -> %s\n' "$HEARTHDB_CURRENT" "$HEARTHDB_VERSION"

if [ "$APPLY" -eq 0 ]; then
    printf '\nReview these versions, then run:\n%s --apply %s %s\n' \
        "$0" "$BOBS_VERSION" "$HEARTHDB_VERSION"
    exit 0
fi

if [ "$BOBS_VERSION" != "$BOBS_CONFIRMED_VERSION" ] ||
   [ "$HEARTHDB_VERSION" != "$HEARTHDB_CONFIRMED_VERSION" ]; then
    echo "error: latest changed after review; run the preview again" >&2
    exit 1
fi

cp "$STAGING/BobsBuddy.zip" "$REPO_ROOT/Vendor/Managed/BobsBuddy.zip"
cp "$STAGING/HearthDb.zip" "$REPO_ROOT/Vendor/Managed/HearthDb.zip"
printf '%s\n' "$BOBS_VERSION" > "$REPO_ROOT/HSTracker/BobsBuddy-version.txt"
printf '%s\n' "$HEARTHDB_VERSION" > "$REPO_ROOT/HSTracker/HearthDb-version.txt"
echo "Updated vendored managed dependencies. Run the Debug build before committing."
