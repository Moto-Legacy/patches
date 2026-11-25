#!/bin/bash
#
# Apply the LineageOS 23.2 patches for Linux 3.4 era devices.
#
# Usage, from the root of a lineage-23.2 tree, after legacy_support_patches:
#   ./patches/apply.sh [path/to/kernel]
#
# The kernel patches are only applied when a kernel path is given.

PACK=$(cd "$(dirname "$0")" && pwd)
TOP=$PWD

apply_dir() {
    local repo=$1 dir=$2
    [ -d "$TOP/$repo" ] || { echo "SKIP: $repo not found"; return; }
    echo "== $repo"
    cd "$TOP/$repo" || exit 1
    for p in "$dir"/*.patch; do
        [ -e "$p" ] || continue
        if ! git am -3 --ignore-whitespace --committer-date-is-author-date "$p"; then
            git am --abort
            echo "ABORT: failed to apply $(basename "$p") in $repo"
            exit 1
        fi
    done
    cd "$TOP"
}

for dir in $(cd "$PACK" && find . -name '*.patch' -not -path './kernel-3.4/*' -exec dirname {} \; | sort -u); do
    repo=${dir#./}
    apply_dir "$repo" "$PACK/$repo"
done

if [ -n "$1" ]; then
    apply_dir "$1" "$PACK/kernel-3.4"
fi

echo "Done."
