#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Vorssaint
set -euo pipefail
cd "${0:A:h:h}"
# Statically link a pinned decoder: sharing the app must not require Homebrew,
# a zstd executable on PATH, Node, or T3 to be installed on the receiving Mac.
readonly revision=f8745da6ff1ad1e7bab384bd1f9d742439278e99
readonly source="$PWD/.build/zstd-source"
if [[ ! -d "$source/.git" ]]; then
    git clone --depth 1 --branch v1.5.7 https://github.com/facebook/zstd.git "$source"
fi
[[ "$(git -C "$source" rev-parse HEAD)" == "$revision" ]] || { print -u2 'Unexpected Zstandard source revision'; exit 1; }
readonly sdk="${1:?Pass the build SDK path}"
readonly flags="-O2 -fPIC -arch arm64 -mmacosx-version-min=14.0 -isysroot $sdk"
readonly stamp="$source/.vorssaint-build-flags"
if [[ "$(cat "$stamp" 2>/dev/null || true)" != "$flags" ]]; then
    make -C "$source/lib" clean >/dev/null
fi
make -C "$source/lib" -j "${VORSS_BUILD_JOBS:-4}" libzstd.a \
    CC="$(xcrun -f clang)" CFLAGS="$flags" ZSTD_LEGACY_SUPPORT=0 \
    ZSTD_LIB_DICTBUILDER=0 ZSTD_LIB_DEPRECATED=0
print -r -- "$flags" > "$stamp"
