#!/bin/bash
#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Script:    fetch_suite.sh
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Fetch the RISC-V Architectural Certification Test suite (ACT4) at a pinned
# revision into sim/arch_test/run/riscv-arch-test/ (gitignored).
#
# The suite is a fetched dependency, not vendored -- see THIRD_PARTY.md.
# rv64 tests are excluded via sparse-checkout: arvern is RV32 only, and they
# account for more than half the working tree.
#----------------------------------------------------------------------------

set -euo pipefail

# Pinned upstream revision. Bump deliberately -- the DUT config, the ELF
# generator and the test sources all move together.
ACT_REPO="https://github.com/riscv/riscv-arch-test"
ACT_BRANCH="act4"
ACT_SHA="a5d6e0235d959b3165ee331d8bc3b49adb038e25"

ARCH_TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUITE_DIR="${ARCH_TEST_DIR}/run/riscv-arch-test"

if [ -d "${SUITE_DIR}/.git" ]; then
    CURRENT_SHA="$(git -C "${SUITE_DIR}" rev-parse HEAD 2>/dev/null || echo none)"
    if [ "${CURRENT_SHA}" == "${ACT_SHA}" ]; then
        echo "Suite already at pinned revision ${ACT_SHA:0:12} -- nothing to do."
        exit 0
    fi
    echo "Suite is at ${CURRENT_SHA:0:12}, want ${ACT_SHA:0:12}."
    echo "Remove ${SUITE_DIR} and re-run to re-fetch."
    exit 1
fi

echo "Fetching ${ACT_REPO} @ ${ACT_SHA:0:12} (branch ${ACT_BRANCH})"
echo "  into ${SUITE_DIR}"

mkdir -p "${SUITE_DIR}"
git -C "${SUITE_DIR}" init -q
git -C "${SUITE_DIR}" remote add origin "${ACT_REPO}"

# Sparse-checkout before the first checkout so the rv64 trees are never
# materialised. --no-cone is required for negative patterns.
git -C "${SUITE_DIR}" config core.sparseCheckout true
git -C "${SUITE_DIR}" sparse-checkout set --no-cone '/*' '!/tests/rv64i' '!/tests/rv64e'

# A pinned SHA needs an explicit fetch -- `clone --depth 1` only ever gets HEAD.
git -C "${SUITE_DIR}" fetch --depth 1 origin "${ACT_SHA}"
git -C "${SUITE_DIR}" checkout -q FETCH_HEAD

# Local patches to the upstream suite. Kept as tracked files under patches/ and
# re-applied on every fetch, because SUITE_DIR is gitignored -- a hand edit there
# is silently lost the next time this script runs.
#
# These fix genuine upstream defects, not aRVern behaviour. Each should be
# reported upstream and dropped from here once it lands.
PATCH_DIR="${ARCH_TEST_DIR}/patches"
if [ -d "${PATCH_DIR}" ]; then
    for patch in "${PATCH_DIR}"/*.patch; do
        [ -e "${patch}" ] || continue
        echo "Applying $(basename "${patch}")"
        if ! git -C "${SUITE_DIR}" apply "${patch}"; then
            echo "ERROR: failed to apply $(basename "${patch}") -- the upstream file" >&2
            echo "       has probably changed. Refresh the patch against ${ACT_SHA:0:12}." >&2
            exit 1
        fi
    done
fi

echo
echo "Fetched $(du -sh "${SUITE_DIR}" | cut -f1) into ${SUITE_DIR}"
echo "Next: ./bin/act_docker --pull   (then ./bin/act_docker make help)"
