#!/usr/bin/env python3
#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Script:    runsim.py
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Master Python driver — single-test and multi-variant runner for arvern RTL simulation.
#----------------------------------------------------------------------------

"""
Run arvern RTL simulation tests.

This unified script handles both individual test execution and full regression suite.
"""

import os
import sys
import subprocess
import argparse
import shutil
import tempfile
import shlex
import time
import random
import platform
import pty
import select
import signal
import fnmatch
import difflib
try:
    import fcntl as _fcntl
except ImportError:
    _fcntl = None   # platform without fcntl (e.g. Windows): embench build lock disabled
from   pathlib import Path
from   typing  import Optional

# Add bin directory to path for imports
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'bin'))
from test_config import TestConfig, get_test_variants, get_variant_log_suffix
from parse_results import (
    parse_test_results_simple as parse_test_results,
    parse_all_results,
    parse_log_file,
    count_results,
    print_detailed_report,
    print_rtl_config,
    print_disabled_skipped_tests,
    print_skipped_failed_tests,
    print_summary_report,
    print_benchmark_statistics
)
import parse_summaries
import flatten_filelist


###======================================================================================================================###
###======================================================================================================================###
###                                                                                                                      ###
###                                                   SOME UTILITIES                                                     ###
###                                                                                                                      ###
###======================================================================================================================###
###======================================================================================================================###

# ANSI color codes
class Colors:
    GREEN        = '\033[32m'
    GREEN_BOLD   = '\033[1m\033[32m'
    RED          = '\033[31m'
    RED_BOLD     = '\033[1m\033[31m'
    YELLOW       = '\033[33m'
    YELLOW_BOLD  = '\033[1m\033[33m'
    VIOLET       = '\033[35m'
    VIOLET_BOLD  = '\033[1m\033[35m'
    NORMAL       = '\033[0m'
    CYAN         = '\033[34m'
    BOLD         = '\033[1m'

def generate_parameterization_file(config: TestConfig, custom_values: Optional[dict] = None, output_dir: Optional[str] = None, quiet: bool = False):
    """
    Auto-generate arv_parameterization.v from RTL configuration.

    Args:
        config: TestConfig instance containing RTL configuration
        custom_values: Optional dictionary of custom parameter values to override defaults
        output_dir: Optional directory to write the file to (default: current directory)
        quiet: If True, suppress the 'Generated' message
    """
    output_file = os.path.join(output_dir, 'arv_parameterization.v') if output_dir else 'arv_parameterization.v'

    # Get RTL configuration from TestConfig
    rtl_config = config._config.get('rtl_config', {})

    if not rtl_config:
        print(f"Warning: No rtl_config found in run_config.json", file=sys.stderr)
        return

    # Generate the file content
    lines = []
    lines.append("//=======================================================================")
    lines.append("//")
    lines.append("// Paramerization of the arvern for the current simulation")
    lines.append("//")
    if custom_values:
        lines.append("// AUTO-GENERATED with custom RTL configuration")
    else:
        lines.append("// AUTO-GENERATED from run_config.json defaults")
    lines.append("//")
    lines.append("//=======================================================================")
    lines.append("")

    # Find maximum parameter name length for alignment
    max_name_len = max(len(name) for name in rtl_config.keys())

    # Add each parameter
    for param_name, param_info in rtl_config.items():
        # Use custom value if provided, otherwise use default
        if custom_values and param_name in custom_values:
            value = custom_values[param_name]
        else:
            value = param_info.get('default', 0)

        description = param_info.get('description', '')

        # Format: parameter  NAME = VALUE;  // Description
        # Use proper spacing for alignment
        spacing = ' ' * (max_name_len - len(param_name))
        lines.append(f"parameter  {param_name}{spacing} =  {value};       // {description}")

    lines.append("")

    # Write the file
    try:
        with open(output_file, 'w') as f:
            f.write('\n'.join(lines))
        if not quiet and not custom_values:
            print(f"Generated {output_file} from run_config.json defaults")
    except IOError as e:
        print(f"Error writing {output_file}: {e}", file=sys.stderr)


def generate_march_config(config: TestConfig, custom_values: Optional[dict] = None, test_name: Optional[str] = None, quiet: bool = False, output_dir: Optional[str] = None):
    """
    Auto-generate march_config.sh with MARCH strings for GCC compilation.

    Args:
        config: TestConfig instance containing RTL configuration
        custom_values: Optional dictionary of custom parameter values to override defaults
        test_name: Optional test name to pick per-test optimization override
        quiet: If True, suppress the 'Generated march_config.sh' message
        output_dir: Optional directory to write the file to (default: current directory)
    """
    output_file = os.path.join(output_dir, 'march_config.sh') if output_dir else 'march_config.sh'

    # Get RTL configuration from TestConfig
    rtl_config = config._config.get('rtl_config', {})

    if not rtl_config:
        print(f"Warning: No rtl_config found in run_config.json", file=sys.stderr)
        return

    # Get parameter values (custom or default)
    def get_value(param_name):
        if custom_values and param_name in custom_values:
            return custom_values[param_name]
        param_info = rtl_config.get(param_name, {})
        return param_info.get('default', 0)

    # Extract configuration values
    base_isa    = get_value('RV32E_EN')
    c_extension = get_value('C_EXTENSION')
    m_extension = get_value('M_EXTENSION')
    b_extension = get_value('B_EXTENSION')

    # RV32E (RV32E_EN=1) mandates the ilp32e ABI; the assembler rejects an
    # rv32e -march paired with -mabi=ilp32 ("only ilp32e/lp64e ABI are
    # supported for e extension"). RV32I uses ilp32.
    mabi = "ilp32e" if base_isa == 1 else "ilp32"

    # Build MARCH string for standard (non-compressed) mode
    march_std = "rv32e" if base_isa == 1 else "rv32i"

    # Add M extension: tier 2 = full M (mul+div, march 'm'); tier 1 = Zmmul
    # (mul-only, march '_zmmul'). Without the elif, M_EXTENSION==1 left march
    # at 'rv32i' with no 'm' / no '_zmmul' ⇒ assembler rejected mul mnemonics
    # in Zmmul-tier builds. Toolchain (binutils 2.40+) accepts '_zmmul' and
    # will refuse div, matching the RTL's M_EXTENSION==1 behaviour.
    if m_extension >= 2:
        march_std += "m"
    elif m_extension == 1:
        march_std += "_zmmul"

    # Add B extension components (independent, based on hierarchy)
    if b_extension >= 1:
        march_std += "_zbb"
    if b_extension >= 2:
        march_std += "_zba"
    if b_extension >= 3:
        march_std += "_zbs"
    if b_extension >= 4:
        march_std += "_zbc"

    # Always add Zicsr (CSR instructions) and Zifencei (FENCE.I instruction)
    march_std += "_zicsr"
    march_std += "_zifencei"

    # Build MARCH string for compressed mode
    march_comp = "rv32e" if base_isa == 1 else "rv32i"

    # Add M extension TIER 2 (full M = 'm' base extension)
    # Tier 1 (Zmmul) is added AFTER 'c' below to keep base extensions before
    # Z-extensions -- otherwise '_zmmul' + 'c' concatenates as '_zmmulc' which
    # GCC parses as a single bogus extension name.
    if m_extension >= 2:
        march_comp += "m"

    # Add C extension (use 'c' for backward compatibility, then add modular extensions)
    if c_extension >= 1:
        march_comp += "c"  # Use 'c' shorthand for base compressed support

    # Add M extension TIER 1 (Zmmul = mul-only) as a Z-extension AFTER 'c'.
    # Canonical order: base extensions ('m','c') then Z-extensions ('_zmmul'...).
    if m_extension == 1:
        march_comp += "_zmmul"

    # Add B extension components (independent, based on hierarchy)
    if b_extension >= 1:
        march_comp += "_zbb"
    if b_extension >= 2:
        march_comp += "_zba"
    if b_extension >= 3:
        march_comp += "_zbs"
    if b_extension >= 4:
        march_comp += "_zbc"

    # Add modular compressed extensions (requires GCC 13+)
    # Note: 'c' flag already includes Zca, but explicit Zcb/Zcmp flags are needed for those features
    if c_extension >= 2:
        march_comp += "_zcb"   # Code-size reduction instructions
    if c_extension >= 3:
        march_comp += "_zcmp"  # Push/pop and double move instructions
    if c_extension >= 4:
        march_comp += "_zcmt"  # Table jump instructions

    # Always add Zicsr and Zifencei
    march_comp += "_zicsr"
    march_comp += "_zifencei"

    # Helper to strip unsupported extensions from a march string
    def strip_unsupported_ext(march, unsupported):
        for ext in unsupported:
            march = march.replace(f"_{ext}", "")
        return march

    # Get toolchain configuration
    toolchain_config = config._config.get('toolchain', {})
    active_profile   = toolchain_config.get('active', 'gcc')
    profiles         = toolchain_config.get('profiles', {})
    profile          = profiles.get(active_profile, {'prefix': 'riscv64-unknown-elf'})

    tc_prefix  = profile.get('prefix', 'riscv64-unknown-elf')
    tc_cc      = profile.get('cc',      f'{tc_prefix}-gcc')
    tc_as      = profile.get('as',      f'{tc_prefix}-as')
    tc_ld      = profile.get('ld',      f'{tc_prefix}-ld')
    tc_objcopy = profile.get('objcopy', f'{tc_prefix}-objcopy')
    tc_objdump = profile.get('objdump', f'{tc_prefix}-objdump')
    tc_size    = profile.get('size',    f'{tc_prefix}-size')
    # Optimization level lives in toolchain.build_config.OPTIMIZATION (parameter-style) alongside LIBC and RODATA_LOCATION
    _build_cfg = toolchain_config.get('build_config', {})
    tc_opt     = _build_cfg.get('OPTIMIZATION', {}).get('default') \
                 or toolchain_config.get('optimization', '-O2')
    tc_desc    = profile.get('description', active_profile)

    # Per-test toolchain override: re-derive all tc_* variables from the new profile
    if test_name:
        test_info = config.get_test_info(test_name)
        if test_info and test_info.get('toolchain'):
            override_name    = test_info['toolchain']
            override_profile = profiles.get(override_name)
            if override_profile:
                active_profile = override_name
                profile        = override_profile
                tc_prefix      = profile.get('prefix', 'riscv64-unknown-elf')
                tc_cc          = profile.get('cc',      f'{tc_prefix}-gcc')
                tc_as          = profile.get('as',      f'{tc_prefix}-as')
                tc_ld          = profile.get('ld',      f'{tc_prefix}-ld')
                tc_objcopy     = profile.get('objcopy', f'{tc_prefix}-objcopy')
                tc_objdump     = profile.get('objdump', f'{tc_prefix}-objdump')
                tc_size        = profile.get('size',    f'{tc_prefix}-size')
                tc_desc        = profile.get('description', override_name)
            else:
                print(f"Warning: Test '{test_name}' specifies toolchain '{override_name}' "
                      f"which is not defined in run_config.json toolchain.profiles", file=sys.stderr)

    # Per-test optimization override
    if test_name:
        test_info = config.get_test_info(test_name)
        if test_info and test_info.get('optimization'):
            global_opt = tc_opt   # already resolved from build_config.OPTIMIZATION (or legacy fallback)
            per_test_opt = test_info['optimization']
            if per_test_opt != global_opt:
                print(f"Note: '{test_name}' overrides global optimization "
                      f"{global_opt} → {per_test_opt} (set in run_config.json tests entry)")
            tc_opt = per_test_opt

    # Auto-detect sysroot for toolchains that need it (e.g. LLVM using GCC's newlib sysroot)
    sysroot = profile.get('sysroot', '')
    if sysroot == 'auto':
        # Detect sysroot and GCC install dir from the default GCC toolchain (xpacks or gcc profile)
        gcc_install_dir = ''
        for fallback_name in ['xpacks', 'gcc']:
            fallback = profiles.get(fallback_name, {})
            fallback_prefix = fallback.get('prefix', '')
            if fallback_prefix:
                try:
                    gcc_cmd = f'{fallback_prefix}-gcc'
                    # Get sysroot (for headers: stdio.h, string.h, etc.)
                    r1 = subprocess.run(
                        [gcc_cmd, '-print-sysroot'],
                        capture_output=True, text=True, timeout=5)
                    # Get libgcc path (for runtime library: libgcc.a)
                    r2 = subprocess.run(
                        [gcc_cmd, f'-march={march_std}', f'-mabi={mabi}', '-print-libgcc-file-name'],
                        capture_output=True, text=True, timeout=5)
                    if r1.returncode == 0 and r1.stdout.strip():
                        sysroot = os.path.realpath(r1.stdout.strip())
                    if r2.returncode == 0 and r2.stdout.strip():
                        gcc_install_dir = os.path.dirname(os.path.realpath(r2.stdout.strip()))
                    if sysroot != 'auto':
                        break
                except (FileNotFoundError, subprocess.TimeoutExpired):
                    continue
        if sysroot == 'auto':
            print("Warning: Could not auto-detect sysroot from GCC toolchain", file=sys.stderr)
            sysroot = ''
    else:
        gcc_install_dir = ''
    if sysroot:
        tc_cc += f' --sysroot={sysroot}'
    if gcc_install_dir:
        tc_cc += f' -rtlib=libgcc --gcc-install-dir={gcc_install_dir}'

    # Strip unsupported extensions for the active toolchain profile
    unsupported = profile.get('unsupported_ext', [])
    if unsupported:
        march_std  = strip_unsupported_ext(march_std,  unsupported)
        march_comp = strip_unsupported_ext(march_comp, unsupported)

    # Generate the shell script content
    lines = []
    lines.append("#!/bin/bash")
    lines.append("#" + "=" * 78)
    lines.append("#")
    lines.append("# Auto-generated MARCH and toolchain configuration")
    lines.append("#")
    if custom_values:
        lines.append("# Generated from custom RTL configuration")
    else:
        lines.append("# Generated from run_config.json defaults")
    lines.append("#")
    lines.append("# RTL Configuration:")
    lines.append(f"#   RV32E_EN    = {base_isa} ({'RV32E' if base_isa == 1 else 'RV32I'}, ABI {mabi})")
    lines.append(f"#   C_EXTENSION = {c_extension} ({['none', 'Zca', 'Zca+Zcb', 'Zca+Zcb+Zcmp', 'Zca+Zcb+Zcmp+Zcmt'][min(c_extension, 4)]})")
    lines.append(f"#   M_EXTENSION = {m_extension} ({['none', 'Zmmul', 'M'][min(m_extension, 2)]})")
    lines.append(f"#   B_EXTENSION = {b_extension} ({['none', 'Zbb', 'Zbb+Zba', 'Zbb+Zba+Zbs'][min(b_extension, 3)]})")
    lines.append("#")
    lines.append(f"# Toolchain: {tc_desc} (profile: {active_profile})")

    # Build configuration: firmware-build axes (optimization, libc, .rodata
    # layout, ...). Lives under toolchain.build_config and is forwarded to
    # Makefiles and Embench's board.cfg as BUILD_<KEY> env vars, with one
    # exception: OPTIMIZATION is emitted as TC_OPT (legacy name) to avoid
    # Makefile churn. Defaults preserve legacy behavior so configs without
    # a build_config block keep building exactly as before.
    build_config = toolchain_config.get('build_config', {})
    build_values = {}
    if build_config:
        lines.append("#")
        lines.append("# Build Configuration:")
        for key, info in build_config.items():
            # OPTIMIZATION is already covered above and emitted as TC_OPT; reflect
            # the post-override value (per-test overrides may have shifted it).
            value = tc_opt if key == 'OPTIMIZATION' else info.get('default')
            build_values[key] = value
            lines.append(f"#   {key:<15} = {value}")
    lines.append("#")
    lines.append("#" + "=" * 78)
    lines.append("")
    lines.append("# MARCH for standard (non-compressed) instruction mode")
    lines.append(f'export MARCH_STD="{march_std}"')
    lines.append("")
    lines.append("# MARCH for compressed instruction mode")
    lines.append(f'export MARCH_COMP="{march_comp}"')
    lines.append("")
    lines.append("# ABI (ilp32e is mandatory for RV32E / RV32E_EN=1)")
    lines.append(f'export MABI="{mabi}"')
    lines.append("")
    lines.append("# Toolchain configuration")
    lines.append(f'export CROSS="{tc_prefix}"')
    lines.append(f'export TC_CC="{tc_cc}"')
    lines.append(f'export TC_AS="{tc_as}"')
    lines.append(f'export TC_LD="{tc_ld}"')
    lines.append(f'export TC_OBJCOPY="{tc_objcopy}"')
    lines.append(f'export TC_OBJDUMP="{tc_objdump}"')
    lines.append(f'export TC_SIZE="{tc_size}"')
    lines.append(f'export TC_OPT="{tc_opt}"')
    lines.append("")
    lines.append("# For use in Makefiles (without export)")
    lines.append(f'MARCH_STD="{march_std}"')
    lines.append(f'MARCH_COMP="{march_comp}"')
    lines.append(f'MABI="{mabi}"')
    lines.append(f'CROSS="{tc_prefix}"')
    lines.append(f'TC_CC="{tc_cc}"')
    lines.append(f'TC_AS="{tc_as}"')
    lines.append(f'TC_LD="{tc_ld}"')
    lines.append(f'TC_OBJCOPY="{tc_objcopy}"')
    lines.append(f'TC_OBJDUMP="{tc_objdump}"')
    lines.append(f'TC_SIZE="{tc_size}"')
    lines.append(f'TC_OPT="{tc_opt}"')
    lines.append("")

    # Build configuration env vars (libc, .rodata layout, ...). Emit only when
    # run_config.json defines a 'toolchain.build_config' block; Makefiles and
    # board.cfg default to legacy behavior (newlib, ROM) if these are unset.
    # OPTIMIZATION is skipped here -- already emitted above as TC_OPT (the
    # legacy name; all existing Makefiles already source TC_OPT).
    _emitted = {k: v for k, v in build_values.items() if k != 'OPTIMIZATION'}
    if _emitted:
        lines.append("# Build configuration (firmware-build axes; see run_config.json 'toolchain.build_config')")
        for key, value in _emitted.items():
            lines.append(f'export BUILD_{key}="{value}"')
        lines.append("")
        lines.append("# For use in Makefiles (without export)")
        for key, value in _emitted.items():
            lines.append(f'BUILD_{key}="{value}"')
        lines.append("")

    # Write the file
    try:
        with open(output_file, 'w') as f:
            f.write('\n'.join(lines))
        # Make it executable
        os.chmod(output_file, 0o755)
        if not custom_values and not quiet:
            print(f"Generated {output_file}: MARCH_STD={march_std}, MARCH_COMP={march_comp}, toolchain={active_profile}, optimization={tc_opt}")
    except IOError as e:
        print(f"Error writing {output_file}: {e}", file=sys.stderr)


def detect_test_type(test_name: str, src_dir: Optional[str] = None, src_c_dir: Optional[str] = None) -> Optional[str]:
    """
    Detect if a test is assembly-based or C-based.

    Args:
        test_name: Name of the test
        src_dir  : Absolute path to src/ directory (default: ../src relative to cwd)
        src_c_dir: Absolute path to src-c/ directory (default: ../src-c relative to cwd)

    Returns:
        'asm' if assembly test (in src/), 'c' if C test (in src-c/), None if not found
    """
    if src_dir is None:
        src_dir = os.path.join(_run_dir, '..', 'src')
    if src_c_dir is None:
        src_c_dir = os.path.join(_run_dir, '..', 'src-c')

    asm_file = Path(os.path.join(src_dir, f'{test_name}.s'))
    c_dir    = Path(os.path.join(src_c_dir, test_name))

    if asm_file.exists():
        return 'asm'
    elif c_dir.exists() and c_dir.is_dir():
        return 'c'
    else:
        return None


def list_available_tests(config: TestConfig, enabled_only: bool = False):
    """
    Print available tests from configuration and discovered tests.

    Args:
        config: TestConfig instance
        enabled_only: If True, only show enabled tests
    """
    tests = config.get_enabled_tests() if enabled_only else config.get_all_tests()

    if enabled_only:
        print(f"\nEnabled tests ({len(tests)}):")
        for test in tests:
            print(f"  {test['name']:20s} {test['mode']:8s} - {test['description']}")
        return  # Skip discovery for enabled-only mode

    # Show registered tests
    print("\nRegistered assembly tests (run_config.json):")

    # Get test categories
    enabled_tests, disabled_tests, skipped_tests = config.get_test_categories()

    print(f"  Total: {len(tests)} registered ({len(enabled_tests)} enabled, {len(disabled_tests)} disabled, {len(skipped_tests)} skipped)")
    print()
    for test in tests:
        is_enabled = test['enabled']
        requires = test.get('requires', '')

        # Determine status
        if not is_enabled:
            status = f"{Colors.RED}disabled"
            requires_str = ""
        elif requires and not config._evaluate_requires(requires):
            status = f"{Colors.CYAN}skipped (requires: {requires})"
            requires_str = f" [requires: {requires}]"
        else:
            status = f"{Colors.GREEN}enabled"
            requires_str = f" [requires: {requires}]" if requires else ""

        print(f"                                          + {test['name']:15s} {'('+test['mode']+')':8s} - {test['description']} [{status}{Colors.NORMAL}]{requires_str}")

    # Discover assembly tests from filesystem
    src_dir = os.path.join(_run_dir, '..', 'src')
    src_c_dir = os.path.join(_run_dir, '..', 'src-c')
    asm_test_files = sorted(Path(src_dir).glob("*.v"))
    registered_names = {test['name'] for test in tests}

    unregistered_asm_tests = []
    for test_file in asm_test_files:
        test_name = test_file.stem
        # Check if corresponding .s file exists
        asm_file = Path(os.path.join(src_dir, f"{test_name}.s"))
        if asm_file.exists() and test_name not in registered_names:
            unregistered_asm_tests.append(test_name)

    if unregistered_asm_tests:
        print(f"\nUnregistered assembly tests (../src/):")
        print(f"  Total: {len(unregistered_asm_tests)} test(s) found but not in run_config.json")
        print()
        for test_name in sorted(unregistered_asm_tests):
            print(f"                                          + {test_name}")

    # Discover C tests from filesystem
    c_test_dirs = sorted([d.name for d in Path(src_c_dir).iterdir() if d.is_dir()])
    print(f"\nC-based tests (../src-c/):")
    if c_test_dirs:
        print(f"  Total: {len(c_test_dirs)} test(s)")
        print()
        for test_name in c_test_dirs:
            print(f"                                          + {test_name}")
    else:
        print("                                          (none found)")


###======================================================================================================================###
###                                                                                                                      ###
###                                           WORK DIRECTORY MANAGEMENT                                                  ###
###                                                                                                                      ###
###======================================================================================================================###

import threading
from concurrent.futures import ThreadPoolExecutor, as_completed


class RunResult:
    """Lightweight subprocess-result shim (just a .returncode), used by
    run_cmd on the cancellation / poll paths where there is no real
    CompletedProcess to return."""
    def __init__(self, rc):
        self.returncode = rc

# Lock for terminal output (prevents interleaved progress bars in parallel mode)
_print_lock = threading.Lock()

# Cancellation event for clean Ctrl+C shutdown of parallel workers
_cancel_event = threading.Event()

# Base directory for all simulations (absolute path, set once at startup)
_run_dir = os.path.abspath('.')

# When True, keep the work dir even on a passing test so the user can inspect
# generated files (pmem.s, simv, traces) after the run. Set in main() based on
# invocation context: True for single-test or -all, False for -regression
# (regressions can produce hundreds of dirs and would blow up disk usage).
_keep_on_success = False
_e_mode = False   # derived in main() from the EFFECTIVE RV32E_EN (==1 => RV32E),
                  # not from the CLI flag alone; drives RV32E trap-handler
                  # selection and the re-run trailer.


def make_progress_bar(variant_results, total, bar_length=34):
    """Create a progress bar string with pass/fail/timeout/aborted coloring in sequence order.

    Args:
        variant_results: List of result status strings: 'pass', 'fail', 'timeout', or 'aborted'
        total: Total number of variants
        bar_length: Width of progress bar in characters
    """
    bar_chars = []
    for i in range(bar_length):
        variant_idx = int((i + 0.5) * total / bar_length) if total > 0 else 0
        if variant_idx < len(variant_results):
            status = variant_results[variant_idx]
            if status == 'pass':
                bar_chars.append(f"{Colors.GREEN_BOLD}█{Colors.NORMAL}")
            elif status == 'timeout':
                bar_chars.append(f"{Colors.YELLOW_BOLD}█{Colors.NORMAL}")
            elif status == 'aborted':
                bar_chars.append(f"{Colors.VIOLET_BOLD}█{Colors.NORMAL}")
            else:
                bar_chars.append(f"{Colors.RED_BOLD}█{Colors.NORMAL}")
        else:
            bar_chars.append('░')
    return f"[{''.join(bar_chars)}] {len(variant_results):2d}/{total:<2d}"


class ParallelDisplay:
    """Thread-safe terminal display for parallel test execution.

    Shows completed tests as scrolling log lines with progress bars,
    and a sticky footer showing one line per active worker.
    """

    def __init__(self, total_modes, start_time, max_name_len):
        self._total = total_modes
        self._completed = 0
        self._start_time = start_time
        self._max_name_len = max_name_len
        self._total_w = len(str(total_modes))
        self._workers = {}       # thread_id -> {test_name, mode, current, total, results}
        self._footer_lines = 0   # number of lines currently drawn in footer

    def on_mode_start(self, test_name, mode_label, total):
        """Called by worker when a mode begins (before any variants run)."""
        tid = threading.get_ident()
        with _print_lock:
            self._workers[tid] = {'test_name': test_name, 'mode': mode_label,
                                  'current': 0, 'total': total, 'results': [],
                                  'started': True}
            self._refresh_footer()

    def on_variant_done(self, test_name, mode_label, current, total, result):
        """Called by worker after each variant completes."""
        tid = threading.get_ident()
        with _print_lock:
            if tid not in self._workers:
                self._workers[tid] = {'test_name': test_name, 'mode': mode_label,
                                      'current': 0, 'total': total, 'results': [],
                                      'started': True}
            w = self._workers[tid]
            w['test_name'] = test_name
            w['mode'] = mode_label
            w['current'] = current
            w['total'] = total
            w['results'].append(result)
            self._refresh_footer()

    def on_mode_done(self, test_name, mode_label, passed, failed, timeout, aborted, variant_results):
        """Called when a test+mode finishes all variants."""
        with _print_lock:
            tid = threading.get_ident()
            self._completed += 1
            self._clear_footer()

            # Print completed line
            ts = self._timestamp()
            pad = ' ' * (self._max_name_len - len(test_name))
            total_v = passed + failed + timeout + aborted
            bar = make_progress_bar(variant_results, total_v)

            summary_parts = [f"{passed} passed"]
            if failed > 0:
                summary_parts.append(f"{Colors.RED_BOLD}{failed} failed{Colors.NORMAL}")
            if timeout > 0:
                summary_parts.append(f"{Colors.YELLOW_BOLD}{timeout} timeout{Colors.NORMAL}")
            if aborted > 0:
                summary_parts.append(f"{Colors.VIOLET_BOLD}{aborted} aborted{Colors.NORMAL}")

            ok = failed == 0 and timeout == 0 and aborted == 0
            status = f"{Colors.GREEN_BOLD}[PASS]{Colors.NORMAL}" if ok else f"{Colors.RED_BOLD}[FAIL]{Colors.NORMAL}"
            sys.stdout.write(f"[{ts}] [{self._completed:{self._total_w}d}/{self._total}] {test_name}{pad} ({mode_label:4s}) {bar} \u2192 {', '.join(summary_parts)} {status}\n")

            # Mark mode done so _draw_footer stops showing this worker.
            if tid in self._workers:
                self._workers[tid]['results'] = []
                self._workers[tid]['started'] = False

            self._draw_footer()

    def remove_worker(self):
        """Called when a worker thread is completely done."""
        tid = threading.get_ident()
        with _print_lock:
            self._workers.pop(tid, None)
            self._clear_footer()
            self._draw_footer()

    def finish(self):
        """Clean up footer when all work is done."""
        with _print_lock:
            self._clear_footer()

    def _timestamp(self):
        elapsed = int(time.time() - self._start_time)
        return f"{elapsed // 60:02d}:{elapsed % 60:02d}"

    def _clear_footer(self):
        """Clear all footer lines (separator + one line per worker)."""
        if self._footer_lines > 0:
            # Cursor is at end of last footer line (no trailing \n).
            # Clear current line, then move up and clear for each remaining line.
            sys.stdout.write(f"\r\033[K")
            for _ in range(self._footer_lines - 1):
                sys.stdout.write(f"\033[A\r\033[K")
            self._footer_lines = 0

    def _draw_footer(self):
        """Draw the footer: separator + one line per active worker."""
        active = [w for w in self._workers.values() if w.get('started')]
        if not active:
            sys.stdout.flush()
            return

        # Separator line
        sep = f"\033[2m{'─' * 70}\033[0m"
        sys.stdout.write(sep)
        lines = 1

        # One line per worker
        for w in active:
            pad = ' ' * (self._max_name_len - len(w['test_name']))
            mini = make_progress_bar(w['results'], w['total'])
            sys.stdout.write(f"\n  {w['test_name']}{pad} ({w['mode']:4s}) {mini}")
            lines += 1

        self._footer_lines = lines
        sys.stdout.flush()

    def _refresh_footer(self):
        """Redraw the footer in place."""
        self._clear_footer()
        self._draw_footer()


def create_work_dir():
    """
    Create a unique work directory under WORK/ for isolated simulation execution.

    Uses tempfile.mkdtemp so the name is unique across processes (not just within
    a single runsim.py invocation), which is required when run_benchmark -j N
    launches multiple ./run sub-processes simultaneously.

    Returns:
        Absolute path to the created work directory (e.g., /path/to/run/WORK/tmpXXXXXX/)
    """
    work_base = os.path.join(_run_dir, 'WORK')
    os.makedirs(work_base, exist_ok=True)
    return tempfile.mkdtemp(dir=work_base)


def setup_work_dir(work_dir, config, custom_values=None, test_name=None):
    """
    Set up a work directory with all necessary generated files.

    Generates arv_parameterization.v, march_config.sh, and an adjusted submit.f
    with paths corrected for the work directory depth.

    Args:
        work_dir: Absolute path to the work directory
        config: TestConfig instance
        custom_values: Optional RTL parameter overrides
        test_name: Optional test name for per-test optimization
    """
    # Generate config files directly into the work directory
    generate_parameterization_file(config, custom_values, output_dir=work_dir, quiet=True)
    generate_march_config(config, custom_values, test_name=test_name, quiet=True, output_dir=work_dir)

    # Generate a fully-flattened submit_sim.f with absolute paths.
    # iverilog resolves ALL paths (in -c files and nested -f files) relative
    # to cwd.  Since the work dir differs from run/, the simulator needs
    # absolute paths and inlined nested -f includes.  Uses the same standalone
    # flatten_filelist.py module that the IPs invoke via rtlsim.sh, so the
    # sim flow is identical across the CPU and the IPs.
    original_submit = os.path.join(_run_dir, '..', '..', '..', 'bench', 'verilog', 'submit.f')
    original_submit = os.path.normpath(original_submit)

    adjusted_submit = os.path.join(work_dir, 'submit_sim.f')

    lines = flatten_filelist.process_filelist(original_submit)
    flatten_filelist.emit_raw(original_submit, lines, adjusted_submit)

    # Expose simulation artifacts at the run/ root via symlinks so they're
    # reachable mid-simulation (live VCD reload, Ctrl+C survives with partial
    # data). The legacy move-at-end logic still runs for asphalt.log when a
    # benchmark sets SIMULATION_TRACE_DEST to a non-default path.  submit_sim.f
    # is also exposed so the user can inspect the flattened filelist after
    # the run, matching the IPs' rtlsim.sh pattern.
    link_artifact(work_dir, 'submit_sim.f')
    if os.environ.get('SIMULATION_NODUMP') != '1':
        link_artifact(work_dir, 'tb_arvern.vcd')
    if os.environ.get('SIMULATION_NOTRACE') != '1' and not os.environ.get('SIMULATION_TRACE_DEST'):
        link_artifact(work_dir, 'asphalt.log')


# Well-known artifact paths that, when produced, are exposed at the run/ root via
# a symlink into the test's work dir. Symlinking at start (rather than moving at
# end) keeps the artifact reachable even if the simulation is Ctrl+C'd, and lets
# tools like GTKWave reload the VCD live during long runs.
_ARTIFACT_NAMES = ('submit_sim.f', 'tb_arvern.vcd', 'asphalt.log')


def make_relative_symlink(target, link_path):
    """Create a relative symlink so the link stays portable and readable.

    Both sides are absolute paths; the symlink itself is stored relative to the
    link's containing directory. Replaces any existing file or symlink at the
    destination. Best-effort — silently no-ops on OSError.
    """
    try:
        if os.path.lexists(link_path):
            os.unlink(link_path)
        rel_target = os.path.relpath(target, start=os.path.dirname(link_path))
        os.symlink(rel_target, link_path)
    except OSError:
        pass


def link_artifact(work_dir, name):
    """Expose work_dir/<name> at run_dir/<name> via a relative symlink."""
    make_relative_symlink(os.path.join(work_dir, name), os.path.join(_run_dir, name))


def clean_dangling_artifact_symlinks():
    """Remove run_dir/<name> entries that are symlinks pointing nowhere.

    Called at the start of a session (after sweep_stale_work_dirs) and at the
    end of each test (after cleanup_work_dir) — any artifact symlink whose
    target dir was just deleted becomes dangling and should be cleared.
    """
    for name in _ARTIFACT_NAMES:
        p = os.path.join(_run_dir, name)
        # os.path.islink returns True for broken symlinks; os.path.exists
        # returns False because it follows the link to a missing target.
        if os.path.islink(p) and not os.path.exists(p):
            try:
                os.unlink(p)
            except OSError:
                pass


def cleanup_work_dir(work_dir, keep_on_failure=False, failed=False):
    """
    Clean up a work directory after simulation.

    Args:
        work_dir: Absolute path to the work directory
        keep_on_failure: If True, keep directory when test failed
        failed: Whether the test failed

    Also honors the module-level _keep_on_success flag — when True and the
    test passed, the dir is kept so the user can inspect post-run artifacts.
    Leftovers from previous invocations are reclaimed by sweep_stale_work_dirs().
    """
    if failed and keep_on_failure:
        return  # Keep for debugging
    if not failed and _keep_on_success:
        return  # Keep for inspection (single-test / -all mode)
    try:
        shutil.rmtree(work_dir)
    except OSError:
        pass  # Best effort cleanup
    # Any artifact symlinks (VCD, asphalt.log) we created at setup time now
    # point into the deleted dir — sweep them so the run/ root stays clean.
    clean_dangling_artifact_symlinks()


def sweep_stale_work_dirs():
    """
    Delete leftover WORK/tmp* directories from previous invocations.

    Called once per top-level runsim.py invocation, before any worker is
    spawned, so concurrent in-process workers (-j N via ThreadPoolExecutor)
    never race against the sweep. When runsim.py is launched as a subprocess
    by an outer orchestrator (e.g. store_benchmark.py with -j N), the
    orchestrator does its own sweep up front and sets RUNSIM_SKIP_SWEEP=1 so
    these subprocess workers skip the sweep — otherwise siblings would delete
    each other's in-flight tmp dirs.

    Reclaims disk from dirs kept by `keep_on_failure=True` after failed tests
    in earlier sessions.
    """
    work_base = os.path.join(_run_dir, 'WORK')
    if not os.path.isdir(work_base):
        clean_dangling_artifact_symlinks()
        return
    import glob
    for d in glob.glob(os.path.join(work_base, 'tmp*')):
        if os.path.isdir(d):
            try:
                shutil.rmtree(d)
            except OSError:
                pass  # Best effort
    # Artifact symlinks from the previous session pointed into dirs we just
    # deleted — clear them now so run/ doesn't hold dangling links.
    clean_dangling_artifact_symlinks()


###======================================================================================================================###
###======================================================================================================================###
###                                                                                                                      ###
###                                           RUN SPECIFIC VARIANT OF A TEST                                             ###
###                                                                                                                      ###
###======================================================================================================================###
###======================================================================================================================###
def run_test_variant(test_name: str, mode_arg: str, variant_args: list, log_dir: Optional[str] = None, seed: Optional[int] = None, tee_output: bool = False, work_dir: Optional[str] = None) -> int:
    """
    Run a single test variant (supports both assembly and C tests).

    Args:
        test_name   : Name of the test
        mode_arg    : Mode argument ('-c_mode' for compressed, '' for standard)
        variant_args: List of variant arguments (wait states, stalls, etc.)
        log_dir     : Directory for log files (if None, output to stdout)
        seed        : Random seed (if None, generate random seed)
        tee_output  : If True, write to both log file AND stdout (like Unix tee)
        work_dir    : Absolute path to work directory (if None, use _run_dir)

    Returns:
        Exit code (0 for success, non-zero for failure)
    """
    # Compute absolute paths from _run_dir
    src_dir    = os.path.join(_run_dir, '..', 'src')
    src_c_dir  = os.path.join(_run_dir, '..', 'src-c')
    bin_dir    = os.path.join(_run_dir, '..', 'bin')

    # Use work_dir if provided, otherwise use _run_dir
    cwd = work_dir if work_dir else _run_dir

    # Detect test type using absolute paths
    test_type = detect_test_type(test_name, src_dir=src_dir, src_c_dir=src_c_dir)
    if test_type is None:
        print(f"Test '{test_name}' not found in {src_dir}/ or {src_c_dir}/", file=sys.stderr)
        return 1

    # Generate random seed if not provided
    if seed is None:
        seed = random.randint(0, 2**31 - 1)

    # Setup file output
    if log_dir:
        # Determine mode suffix for log filename
        mode_suffix = '-c' if mode_arg == '-c_mode' else '-std'
        suffix      = get_variant_log_suffix(variant_args)
        log_file    = os.path.join(log_dir, f"{test_name}{mode_suffix}{suffix}.log")
        output_file = open(log_file, 'w')
        if tee_output:
            print(f"Logging to: {log_file}")
    else:
        output_file = None

    def run_cmd(cmd, **kwargs):
        """Helper to run command with proper output redirection."""
        if output_file and tee_output:
            # Tee mode: write to both file and stdout in real-time
            # Use pty to prevent buffering - creates pseudo-terminal so subprocess uses line buffering

            # Bind a write-once non-None alias: output_file is a closure
            # free-var (TextIO | None); the nested function below cannot keep
            # the outer truthiness narrowing, so capture the narrowed handle.
            out_f = output_file

            def tee_output_realtime(cmd_list):
                """Run command with real-time output to both stdout and file using pty."""
                # Create a pseudo-terminal to prevent output buffering
                master, slave = pty.openpty()

                # Start the process with the slave side of the pty
                # Use preexec_fn to create a new process group so we can kill all children
                process = subprocess.Popen(
                    cmd_list,
                    stdout=slave,
                    stderr=slave,
                    preexec_fn=os.setsid,  # Create new process group
                    **kwargs
                )

                # Close slave in parent process
                os.close(slave)

                # Read from master and write to both stdout and file
                try:
                    while True:
                        # Check for cancellation (parallel mode Ctrl+C)
                        if _cancel_event.is_set():
                            try:
                                os.killpg(os.getpgid(process.pid), signal.SIGKILL)
                                process.wait()
                            except Exception:
                                pass
                            break

                        # Check if there's data to read (with timeout)
                        ready, _, _ = select.select([master], [], [], 0.1)
                        if ready:
                            try:
                                data = os.read(master, 1024)
                                if not data:
                                    break
                                # Decode and write to both stdout and file
                                text = data.decode('utf-8', errors='replace')
                                sys.stdout.write(text)
                                sys.stdout.flush()
                                out_f.write(text)
                                out_f.flush()
                            except OSError:
                                break

                        # Check if process has finished
                        if process.poll() is not None:
                            # Read any remaining data
                            try:
                                while True:
                                    data = os.read(master, 1024)
                                    if not data:
                                        break
                                    text = data.decode('utf-8', errors='replace')
                                    sys.stdout.write(text)
                                    sys.stdout.flush()
                                    out_f.write(text)
                                    out_f.flush()
                            except OSError:
                                pass
                            break
                except KeyboardInterrupt:
                    # User pressed Ctrl-C - kill the subprocess and all its children
                    print("\nInterrupted by user (Ctrl-C). Terminating subprocess and all children...", file=sys.stderr)
                    try:
                        # Kill the entire process group to ensure all children (including vpp) are terminated
                        pgid = os.getpgid(process.pid)
                        os.killpg(pgid, signal.SIGTERM)

                        # Wait up to 2 seconds for graceful shutdown
                        try:
                            process.wait(timeout=2)
                        except subprocess.TimeoutExpired:
                            # Force kill if terminate didn't work
                            print("Process group didn't terminate gracefully, sending SIGKILL...", file=sys.stderr)
                            os.killpg(pgid, signal.SIGKILL)
                            process.wait()
                    except Exception as e:
                        # If process group kill fails, try killing just the main process
                        print(f"Warning: Failed to kill process group ({e}), trying main process...", file=sys.stderr)
                        try:
                            process.kill()
                            process.wait()
                        except:
                            pass
                    # Re-raise the exception so the script exits properly
                    raise
                finally:
                    os.close(master)

                # Wait for process to finish
                returncode = process.wait()

                # Return a result-like object
                class TeeResult:
                    def __init__(self, rc):
                        self.returncode = rc
                return TeeResult(returncode)

            return tee_output_realtime(cmd)
        elif output_file:
            # File only mode - use Popen for better control over process group cleanup
            process = subprocess.Popen(
                cmd,
                stdout=output_file,
                stderr=subprocess.STDOUT,
                preexec_fn=os.setsid,  # Create new process group
                **kwargs
            )
            try:
                # Poll instead of blocking wait so we can respond to cancellation
                while process.poll() is None:
                    if _cancel_event.is_set():
                        try:
                            os.killpg(os.getpgid(process.pid), signal.SIGKILL)
                            process.wait()
                        except Exception:
                            pass
                        return RunResult(-9)
                    time.sleep(0.2)
                return RunResult(process.returncode)
            except KeyboardInterrupt:
                print("\nInterrupted by user (Ctrl-C). Terminating subprocess and all children...", file=sys.stderr)
                try:
                    pgid = os.getpgid(process.pid)
                    os.killpg(pgid, signal.SIGTERM)
                    try:
                        process.wait(timeout=2)
                    except subprocess.TimeoutExpired:
                        os.killpg(pgid, signal.SIGKILL)
                        process.wait()
                except Exception as e:
                    print(f"Warning: Failed to kill process group ({e}), trying main process...", file=sys.stderr)
                    try:
                        process.kill()
                        process.wait()
                    except:
                        pass
                raise
        else:
            # Stdout only mode - use Popen for better control over process group cleanup
            process = subprocess.Popen(
                cmd,
                preexec_fn=os.setsid,  # Create new process group
                **kwargs
            )
            try:
                # Poll instead of blocking wait so we can respond to cancellation
                while process.poll() is None:
                    if _cancel_event.is_set():
                        try:
                            os.killpg(os.getpgid(process.pid), signal.SIGKILL)
                            process.wait()
                        except Exception:
                            pass
                        return RunResult(-9)
                    time.sleep(0.2)
                return RunResult(process.returncode)
            except KeyboardInterrupt:
                print("\nInterrupted by user (Ctrl-C). Terminating subprocess and all children...", file=sys.stderr)
                try:
                    pgid = os.getpgid(process.pid)
                    os.killpg(pgid, signal.SIGTERM)
                    try:
                        process.wait(timeout=2)
                    except subprocess.TimeoutExpired:
                        os.killpg(pgid, signal.SIGKILL)
                        process.wait()
                except Exception as e:
                    print(f"Warning: Failed to kill process group ({e}), trying main process...", file=sys.stderr)
                    try:
                        process.kill()
                        process.wait()
                    except:
                        pass
                raise

    try:
        # Determine paths based on test type (all absolute)
        # Both branches bind all of linkfile/srcdir_c/lstfile so they are never
        # possibly-unbound. The cross-branch ones use an empty-string sentinel
        # (kept as str, not None, so stdlib path calls stay type-clean) and are
        # only ever read inside their own test_type block.
        if test_type == 'asm':
            srcfile    = os.path.join(src_dir, f'{test_name}.s')
            verfile    = os.path.join(src_dir, f'{test_name}.v')
            linkfile   = os.path.join(bin_dir, 'link.ld')
            srcdir_c   = ''
            lstfile    = ''
        else:  # test_type == 'c'
            srcdir_c   = os.path.join(src_c_dir, test_name)
            srcfile    = os.path.join(srcdir_c, f'{test_name}.elf')
            verfile    = os.path.join(srcdir_c, f'{test_name}.v')
            lstfile    = os.path.join(srcdir_c, f'{test_name}.lst')
            linkfile   = ''

        # Submit file: use work dir copy (with adjusted paths) if available
        if work_dir and os.path.exists(os.path.join(work_dir, 'submit_sim.f')):
            submitfile = os.path.join(work_dir, 'submit_sim.f')
        else:
            submitfile = os.path.normpath(os.path.join(_run_dir, '..', '..', '..', 'bench', 'verilog', 'submit.f'))

        # Check if ISIM simulator
        if os.environ.get('VERILOG_SIMULATOR') == 'isim':
            submitfile = os.path.normpath(os.path.join(_run_dir, '..', '..', '..', 'bench', 'verilog', 'submit.prj'))

        # Check required files exist
        if not os.path.exists(verfile):
            print(f"Verilog stimulus file doesn't exist: {verfile}", file=sys.stderr)
            return 1
        if not os.path.exists(submitfile):
            print(f"Verilog submit file doesn't exist: {submitfile}", file=sys.stderr)
            return 1
        if test_type == 'asm':
            if not os.path.exists(srcfile):
                print(f"Assembler file doesn't exist: {srcfile}", file=sys.stderr)
                return 1
            if not os.path.exists(linkfile):
                print(f"Linker definition file doesn't exist: {linkfile}", file=sys.stderr)
                return 1

        # Cleanup old files in work directory
        cleanup_files = ['pmem.s',   'pmem.ld',   'stimulus.v', 'pmem.elf', 'pmem.ihex',
                         'pmem.lst', 'pmem.size', 'pmem.mem',   'probes_variables.v']
        for f in cleanup_files:
            fpath = os.path.join(cwd, f)
            if os.path.exists(fpath):
                os.remove(fpath)

        # Create symlinks (or copy on Cygwin)
        is_cygwin = 'CYGWIN' in os.uname().sysname if hasattr(os, 'uname') else False

        if test_type == 'asm':
            if is_cygwin:
                shutil.copy(srcfile,  os.path.join(cwd, 'pmem.s'))
                shutil.copy(verfile,  os.path.join(cwd, 'stimulus.v'))
                shutil.copy(linkfile, os.path.join(cwd, 'pmem.ld'))
            else:
                make_relative_symlink(srcfile,  os.path.join(cwd, 'pmem.s'))
                make_relative_symlink(verfile,  os.path.join(cwd, 'stimulus.v'))
                make_relative_symlink(linkfile, os.path.join(cwd, 'pmem.ld'))
        else:  # C test
            if is_cygwin:
                shutil.copy(verfile,  os.path.join(cwd, 'stimulus.v'))
            else:
                make_relative_symlink(verfile, os.path.join(cwd, 'stimulus.v'))

        # Determine instruction mode
        inst_mode = 'COMP_MODE' if mode_arg == '-c_mode' else 'STD_MODE'

        # Check if random IRQ injection is requested
        random_irq = '-rirq' in variant_args
        # Check if the AHB-Lite protocol checker is requested (off by default)
        ahb_check  = '-ahb_check' in variant_args

        # Build per-subprocess environment (thread-safe, no os.environ mutation)
        sub_env = os.environ.copy()
        sub_env['BIN_DIR'] = bin_dir
        if work_dir:
            sub_env['CHECKER_DATA_DIR'] = work_dir

        # Step 1: Compile and link
        if test_type == 'asm':
            # Assembly test: use asm2ihex.sh
            # Always link the random IRQ trap handler for instrumented tests
            # (the handler is harmless when no IRQs are injected). For an RV32E
            # build (effective RV32E_EN==1, via -e_mode OR a run_config.json
            # default of 1) the shared RV32I handler cannot assemble (it names
            # x28-x31), so link the behaviourally-identical RV32E variant
            # (x0-x15 only). _e_mode is derived from the effective RV32E_EN.
            trap_handler = os.path.join(
                src_dir,
                'random_irq_trap_handler_rv32e.s' if _e_mode
                else 'random_irq_trap_handler.s')
            asm_cmd = [os.path.join(bin_dir, 'asm2ihex.sh'), 'pmem', 'pmem.s', 'pmem.ld', inst_mode,
                       trap_handler]
            result = run_cmd(asm_cmd, cwd=cwd, env=sub_env)
            if result.returncode != 0 or not os.path.exists(os.path.join(cwd, 'pmem.ihex')):
                if output_file:
                    output_file.write("ERROR: Cannot find pmem.ihex file.\n")
                return 1
        else:
            # C test: use c2ihex.sh
            #
            # Embench benchmarks all share embench-iot/bd as their build output dir.
            # build_all.py --clean destroys and recreates bd/ on every invocation, so
            # concurrent c2ihex.sh calls for different embench tests would race on bd/.
            # Serialize the entire compilation block (c2ihex + symlink + objcopy) with
            # an exclusive file lock so only one embench build runs at a time.
            # The lock is released as soon as pmem.ihex is safely written to the WORK
            # dir — from that point the simulation is self-contained and bd/ can be
            # safely rebuilt by the next waiting worker.
            _embench_lock_fd = None
            if test_name.startswith('embench_') and _fcntl is not None:
                _lock_path = os.path.join(src_c_dir, 'embench-iot', '.build.lock')
                _embench_lock_fd = open(_lock_path, 'w')
                _fcntl.flock(_embench_lock_fd, _fcntl.LOCK_EX)
            try:
                result = run_cmd([os.path.join(bin_dir, 'c2ihex.sh'), srcdir_c, inst_mode], cwd=cwd, env=sub_env)
                if result.returncode != 0:
                    if output_file:
                        output_file.write("ERROR: C compilation failed.\n")
                    return 1

                # Create symlinks to generated files
                elf_path = os.path.join(cwd, 'pmem.elf')
                if is_cygwin:
                    shutil.copy(srcfile, elf_path)
                else:
                    make_relative_symlink(srcfile, elf_path)

                # Convert ELF to IHEX (read objcopy tool from march_config.sh)
                objcopy_cmd = 'riscv64-unknown-elf-objcopy'  # default fallback
                march_config_path = os.path.join(cwd, 'march_config.sh')
                if os.path.exists(march_config_path):
                    try:
                        r = subprocess.run(['bash', '-c', f'source {march_config_path} && echo $TC_OBJCOPY'],
                                           capture_output=True, text=True)
                        if r.returncode == 0 and r.stdout.strip():
                            objcopy_cmd = r.stdout.strip()
                    except Exception:
                        pass
                result = run_cmd([objcopy_cmd, '-O', 'ihex', 'pmem.elf', 'pmem.ihex'], cwd=cwd, env=sub_env)
                if result.returncode != 0 or not os.path.exists(os.path.join(cwd, 'pmem.ihex')):
                    if output_file:
                        output_file.write("ERROR: Cannot find pmem.ihex file.\n")
                    return 1
            finally:
                if _embench_lock_fd is not None and _fcntl is not None:
                    _fcntl.flock(_embench_lock_fd, _fcntl.LOCK_UN)
                    _embench_lock_fd.close()

        # Step 2: Convert IHEX to memory format (ihex2mem.py)
        result = run_cmd([
            'python3', os.path.join(bin_dir, 'ihex2mem.py'), '--ihex',            'pmem.ihex',
                                                              '--out',             'pmem.mem',
                                                              '--mem_base_offset', '0x20000000',
                                                              '--mem_size',        '65536'
        ], cwd=cwd, env=sub_env)
        if result.returncode != 0 or not os.path.exists(os.path.join(cwd, 'pmem.mem')):
            if output_file:
                output_file.write("ERROR: Cannot find pmem.mem file.\n")
            return 1

        # Step 3: Generate symbol probes (gen_symbol_probes.py)
        # Use appropriate lst file based on test type
        if test_type == 'asm':
            lst_path = './pmem.lst'
        else:  # C test
            lst_path = lstfile

        result = run_cmd([
            'python3', os.path.join(bin_dir, 'gen_symbol_probes.py'), '--lst',              lst_path,
                                                                      '--out',              './probes_variables.v',
                                                                      '--sram_base_offset', '0x81000000'
        ], cwd=cwd, env=sub_env)
        if result.returncode != 0 or not os.path.exists(os.path.join(cwd, 'probes_variables.v')):
            if output_file:
                output_file.write("ERROR: Cannot find probes_variables.v file.\n")
            return 1

        # Step 4: Build rtlsim.sh arguments
        top       = 'tb_arvern'

        # Parse variant arguments to determine defines
        rom_ws    = 'ROM_ZERO_WS'
        sram_ws   = 'SRAM_ZERO_WS'
        periph_ws = 'PERIPH_ZERO_WS'
        alu_stall = 'ALU_ZERO_STALL'
        ahb_type  = 'HIPERF_AHB'

        for arg in variant_args:
            if   arg == '-rwsrom':
                rom_ws    = 'ROM_RANDOM_WS'
            elif arg == '-wsrom':
                rom_ws    = 'ROM_WS'
            elif arg == '-rwsram':
                sram_ws   = 'SRAM_RANDOM_WS'
            elif arg == '-wssram':
                sram_ws   = 'SRAM_WS'
            elif arg == '-rwsper':
                periph_ws = 'PERIPH_RANDOM_WS'
            elif arg == '-wsper':
                periph_ws = 'PERIPH_WS'
            elif arg == '-rsalu':
                alu_stall = 'ALU_RANDOM_STALL'
            elif arg == '-salu':
                alu_stall = 'ALU_STALL'
            elif arg == '-gahb':
                ahb_type  = 'GENERIC_AHB'
            elif arg == '-fahb':
                ahb_type  = 'FUSED_AHB'

        # Step 5: Run simulation (rtlsim.sh)
        # Compose extra defines (thread-safe via sub_env). Multiple sources may
        # contribute (random IRQ injection, AHB protocol checker), so build a
        # list rather than overwrite.
        extra_parts = []
        if random_irq:
            extra_parts.append('-D RANDOM_IRQ -D LONG_TIMEOUT')
        if ahb_check:
            extra_parts.append('-D AHB_PROTOCOL_CHECK')
        if extra_parts:
            sub_env['SIMULATION_EXTRA_DEFINES'] = ' '.join(extra_parts)
        else:
            sub_env.pop('SIMULATION_EXTRA_DEFINES', None)

        # On macOS, use caffeinate to prevent sleep during simulation
        sim_cmd = [
            os.path.join(bin_dir, 'rtlsim.sh'), top,
                                'stimulus.v',
                                submitfile,
                                str(seed),
                                rom_ws,
                                sram_ws,
                                periph_ws,
                                alu_stall,
                                ahb_type,
                                inst_mode,
        ]

        # Wrap with caffeinate on macOS to prevent sleep
        if platform.system() == 'Darwin':
            sim_cmd = ['caffeinate', '-i'] + sim_cmd

        result = run_cmd(sim_cmd, cwd=cwd, env=sub_env)

        # Print re-run command (only for single test mode, not regression)
        if log_dir is None:
            cmd_parts = ['> ./run', test_name, mode_arg]
            if _e_mode:
                cmd_parts.append('-e_mode')
            cmd_parts.extend(variant_args)
            cmd_parts.append(f'-seed {seed}')
            print(f"\nTo re-run this test:  {' '.join(cmd_parts)}\n")

        return result.returncode

    finally:
        if output_file:
            output_file.close()

###======================================================================================================================###
###======================================================================================================================###
###                                                                                                                      ###
###                                           RUN ALL VARIANTS OF A SINGLE TEST                                          ###
###                                                                                                                      ###
###======================================================================================================================###
###======================================================================================================================###

def _run_mode_variants(test_name, mode_arg, variants, total_variants, log_dir, work_dir,
                       indent=30, display=None):
    """
    Run all timing variants for a single mode (STD or COMP).

    Args:
        test_name      : Name of the test
        mode_arg       : '-c_mode' for compressed, '' for standard
        variants       : List of variant argument lists to run
        total_variants : Total number of variants (for progress bar)
        log_dir        : Directory for log files
        work_dir       : Work directory for simulation files
        indent         : Indentation for sequential progress bar
        display        : ParallelDisplay instance (None for sequential mode)

    Returns:
        (variant_results, mode_passed) where variant_results is list of 'pass'/'fail'/etc.
    """
    mode_label = "COMP" if mode_arg == '-c_mode' else "STD "
    mode_desc  = "COMPRESSED" if mode_arg == '-c_mode' else "STANDARD  "

    variant_results = []
    prev_passed = prev_failed = prev_timeout = prev_aborted = 0

    if display:
        display.on_mode_start(test_name, mode_label, total_variants)

    # Show initial progress bar (sequential mode only)
    if display is None:
        if log_dir:
            bar = make_progress_bar(variant_results, total_variants)
            print(f"{' ' * indent}{mode_desc} instruction run... {bar}", end='', flush=True)
        else:
            print(f"{' ' * indent}{mode_desc} instruction run... ", end='', flush=True)

    for i, vargs in enumerate(variants, 1):
        if _cancel_event.is_set():
            break
        run_test_variant(test_name, mode_arg, vargs, log_dir, work_dir=work_dir)

        if log_dir:
            passed, failed, timeout, aborted = parse_test_results(test_name, mode_arg, log_dir)
            if passed > prev_passed:
                variant_results.append('pass')
            elif timeout > prev_timeout:
                variant_results.append('timeout')
            elif aborted > prev_aborted:
                variant_results.append('aborted')
            elif failed > prev_failed:
                variant_results.append('fail')
            else:
                variant_results.append('fail')
            prev_passed, prev_failed = passed, failed
            prev_timeout, prev_aborted = timeout, aborted

            if display:
                display.on_variant_done(test_name, mode_label, i, total_variants, variant_results[-1])
            else:
                bar = make_progress_bar(variant_results, total_variants)
                print(f"\r{' ' * indent}{mode_desc} instruction run... {bar}", end='', flush=True)

    # Summary
    mode_passed = True
    if log_dir:
        passed, failed, timeout, aborted = parse_test_results(test_name, mode_arg, log_dir)
        if display:
            display.on_mode_done(test_name, mode_label, passed, failed, timeout, aborted, variant_results)
        else:
            ok = failed == 0 and timeout == 0 and aborted == 0
            status = f"{Colors.GREEN_BOLD}[PASS]{Colors.NORMAL}" if ok else f"{Colors.RED_BOLD}[FAIL]{Colors.NORMAL}"
            summary_parts = [f"{passed} passed"]
            if failed > 0:
                summary_parts.append(f"{Colors.RED_BOLD}{failed} failed{Colors.NORMAL}")
            if timeout > 0:
                summary_parts.append(f"{Colors.YELLOW_BOLD}{timeout} timeout{Colors.NORMAL}")
            if aborted > 0:
                summary_parts.append(f"{Colors.VIOLET_BOLD}{aborted} aborted{Colors.NORMAL}")
            print(f" → {', '.join(summary_parts)} {status}")
        if failed > 0 or timeout > 0 or aborted > 0:
            mode_passed = False
    else:
        if display is None:
            print()

    return variant_results, mode_passed


def run_all_variants(test_name: str, config: TestConfig, log_dir: Optional[str] = None, mode_override: Optional[str] = None,
                     indent: int = 30, work_dir: Optional[str] = None, variant_args: Optional[list] = None, display=None,
                     custom_values: Optional[dict] = None):
    """
    Run a test based on its configuration (STD, COMP, or BOTH modes).

    Args:
        test_name: Name of the test
        config   : TestConfig instance
        log_dir  : Directory for log files (if None, output to stdout)
        mode_override: Optional mode override ('STD' or 'COMP') to ignore test configuration
        work_dir : If provided, use this work directory instead of creating one
        variant_args : If provided, run only this single variant instead of all timing variants
        display      : ParallelDisplay instance for parallel mode (None for sequential)

    Returns:
        True if all tests passed, False if any tests failed
    """
    mode = mode_override if mode_override else config.get_test_mode(test_name)

    # Create a work directory for this test (isolates all generated files)
    own_work_dir = work_dir is None
    if own_work_dir:
        work_dir = create_work_dir()
    setup_work_dir(work_dir, config, custom_values=custom_values, test_name=test_name)

    # Use specified variant or generate all timing variants
    if variant_args is not None:
        variants = [variant_args]
    else:
        variants = get_test_variants()

    # Filter out random IRQ variants for tests that have no_random_irq set
    if config.is_no_random_irq(test_name):
        variants = [v for v in variants if '-rirq' not in v]

    # Filter out random ALU stall variants for tests that have no_rsalu set
    # (ALU stalls keep the pipeline full, suppressing some pipeline-timing-sensitive events)
    if config.is_no_rsalu(test_name):
        variants = [v for v in variants if '-rsalu' not in v]

    # Filter out random ROM wait state variants for tests that have no_rwsrom set
    # (ROM WS increases instruction spacing, resolving some load-use hazards before EX stage)
    if config.is_no_rwsrom(test_name):
        variants = [v for v in variants if '-rwsrom' not in v]

    # Filter out fused AHB variants for tests that have no_fahb set
    # (fused interconnect bypasses the ROM/SRAM_X wait-state inserters, so tests that
    # rely on injected ROM/SRAM_X wait states cannot exercise their intended scenario)
    if config.is_no_fahb(test_name):
        variants = [v for v in variants if '-fahb' not in v]

    # Skip all timing variants for tests that require exact pipeline timing
    if config.is_no_variants(test_name) and variant_args is None:
        variants = [variants[0]]  # Keep only the base variant (no wait states)

    total_variants = len(variants)
    all_passed = True

    if mode == 'BOTH':
        _, std_passed = _run_mode_variants(test_name, '', variants, total_variants, log_dir, work_dir, indent, display)
        _, comp_passed = _run_mode_variants(test_name, '-c_mode', variants, total_variants, log_dir, work_dir, indent, display)
        all_passed = std_passed and comp_passed
    elif mode == 'COMP':
        _, all_passed = _run_mode_variants(test_name, '-c_mode', variants, total_variants, log_dir, work_dir, indent, display)
    else:  # STD
        _, all_passed = _run_mode_variants(test_name, '', variants, total_variants, log_dir, work_dir, indent, display)

    # When SIMULATION_TRACE_DEST is set (benchmark mode), move asphalt.log out
    # of the work dir to the per-benchmark destination — that path differs per
    # benchmark (e.g. asphalt_coremark.log) and isn't covered by the symlink at
    # run/asphalt.log. The default-named asphalt.log and the VCD are exposed
    # via symlinks created in setup_work_dir(), so they need no end-of-run move.
    if own_work_dir and os.environ.get('SIMULATION_NOTRACE') != '1':
        trace_dest = os.environ.get('SIMULATION_TRACE_DEST')
        if trace_dest:
            work_trace = os.path.join(work_dir, 'asphalt.log')
            if os.path.exists(work_trace):
                shutil.move(work_trace, trace_dest)

    # Cleanup work directory (keep on failure for debugging)
    if own_work_dir:
        cleanup_work_dir(work_dir, keep_on_failure=True, failed=not all_passed)

    if display:
        display.remove_worker()

    return all_passed


###======================================================================================================================###
###======================================================================================================================###
###                                                                                                                      ###
###                                               RUN FULL REGRESSION                                                    ###
###                                                                                                                      ###
###                                     (will run all variants of all enabled tests)                                     ###
###                                                                                                                      ###
###======================================================================================================================###
###======================================================================================================================###
def run_regression(iteration: int, config: TestConfig, stop_on_fail: bool = False, show_all_report: bool = False, jobs: int = 1, variant_args: Optional[list] = None):
    """
    Run a single regression iteration with all enabled tests.

    Args:
        iteration       : Iteration number (for log directory naming)
        config          : TestConfig instance
        stop_on_fail    : If True, stop after first test failure
        show_all_report : If True, show all tests in detailed report; if False, only show failures/timeouts
        jobs            : Number of parallel test slots (default: 1 = sequential)
        variant_args    : If provided, run only this single variant instead of all timing variants

    Returns:
        True if all tests passed, False if any tests failed
    """
    # Setup log directory
    log_dir = f'./log/{iteration}'
    os.makedirs(log_dir, exist_ok=True)

    # Get test categories
    enabled_tests, disabled_tests, skipped_tests = config.get_test_categories()

    print(f"\n{'=' * 70}")
    print(f"Regression iteration {iteration}")
    print(f"{'=' * 70}")
    print(f"Reading test list from run_config.json...")
    disabled_non_bench = [t for t in disabled_tests if not t.get('is_benchmark', False)]
    print(f"Found {len(enabled_tests)} enabled tests")
    if disabled_non_bench:
        print(f"      {len(disabled_non_bench)} disabled tests")
    if skipped_tests:
        print(f"      {len(skipped_tests)} skipped tests (requirements not met)")
    print()

    # ANSI color codes
    CYAN  = '\033[34m'
    BOLD  = '\033[1m'
    RESET = '\033[0m'

    # Record start time for elapsed time tracking
    start_time = time.time()

    # Track if any test failed
    any_test_failed = False

    # Pre-compute alignment constants for consistent column alignment
    n_tests      = len(enabled_tests)
    n_tests_w    = len(str(n_tests))   # digit width of total (e.g. 3 for 123 tests)
    max_name_len = max((len(t['name']) for t in enabled_tests), default=0)
    # Prefix: "[MM:SS] [NNN/NNN] Running test: " — 7+1+(1+w+1+w+1)+1+14 = 26 + 2*w chars
    sub_indent   = 26 + 2 * n_tests_w + max_name_len + 1

    # Run each enabled test
    if jobs <= 1:
        # Sequential mode: progress bars and elapsed timestamps
        for i, test in enumerate(enabled_tests, 1):
            test_name      = test['name']
            test_mode      = test['mode']
            test_toolchain = test.get('toolchain') or config._config.get('toolchain', {}).get('active', 'gcc')

            # Calculate elapsed time
            elapsed_seconds = int(time.time() - start_time)
            minutes   = elapsed_seconds // 60
            seconds   = elapsed_seconds % 60
            timestamp = f"{minutes:02d}:{seconds:02d}"

            pad = ' ' * (max_name_len - len(test_name))
            print(f"[{timestamp}] [{i:{n_tests_w}d}/{n_tests}] Running test: {CYAN}{BOLD}{test_name}{RESET}{pad} (mode: {test_mode}, toolchain: {test_toolchain})")
            test_passed = run_all_variants(test_name, config, log_dir, indent=sub_indent, variant_args=variant_args)

            # Check if we should stop on failure
            if stop_on_fail and not test_passed:
                any_test_failed = True
                print(f"\n{Colors.RED_BOLD}Test '{test_name}' failed. Stopping regression due to --stop-on-fail{Colors.NORMAL}\n")
                break

            if not test_passed:
                any_test_failed = True
    else:
        # Parallel mode: run tests concurrently with ThreadPoolExecutor
        # Each test reports progress via ParallelDisplay (scrolling log + live footer)
        total_modes = sum(2 if t['mode'] == 'BOTH' else 1 for t in enabled_tests)
        display = ParallelDisplay(total_modes, start_time, max_name_len)

        def run_test_parallel(test):
            """Run a single test in its own work directory."""
            test_name = test['name']
            test_passed = run_all_variants(test_name, config, log_dir, indent=0, variant_args=variant_args, display=display)
            return test_name, test_passed

        print(f"Running {n_tests} tests ({total_modes} test+mode combinations) with {jobs} parallel workers...")
        print()

        # Pre-bind before the try so an early KeyboardInterrupt (even before
        # the comprehension) can't NameError in the except cancel loop.
        futures = {}
        try:
            with ThreadPoolExecutor(max_workers=jobs) as pool:
                futures = {pool.submit(run_test_parallel, test): test for test in enabled_tests}
                for future in as_completed(futures):
                    test_name, test_passed = future.result()
                    if not test_passed:
                        any_test_failed = True
        except KeyboardInterrupt:
            _cancel_event.set()
            display.finish()
            print(f"\n{Colors.YELLOW_BOLD}Interrupted — cancelling remaining tests...{Colors.NORMAL}")
            for f in futures:
                f.cancel()
            return False

        display.finish()

    # Report regression results
    print(f"\n{'=' * 70}")
    print(f"Parsing results for iteration {iteration}...")
    print(f"{'=' * 70}\n")

    # Parse all results
    results = parse_all_results(log_dir)

    # Get RTL configuration
    rtl_config = config.get_rtl_config()

    # Write to summary log file
    summary_log = f'{log_dir}/../summary.{iteration}.log'
    with open(summary_log, 'w') as f:
        # Redirect stdout to file temporarily
        old_stdout = sys.stdout
        sys.stdout = f
        try:
            print_detailed_report(results, show_all=show_all_report)
            print_rtl_config(rtl_config)
            print_disabled_skipped_tests(disabled_tests, skipped_tests)
            print_skipped_failed_tests(results)
            print_summary_report(results)
        finally:
            sys.stdout = old_stdout

    # Also print to stdout
    print_detailed_report(results, show_all=show_all_report)
    print_rtl_config(rtl_config)
    print_disabled_skipped_tests(disabled_tests, skipped_tests)
    print_skipped_failed_tests(results)
    print_summary_report(results)

    return not any_test_failed


###======================================================================================================================###
###======================================================================================================================###
###                                                                                                                      ###
###                                                       MAIN                                                           ###
###                                                                                                                      ###
###======================================================================================================================###
###======================================================================================================================###
def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description='Run arvern RTL simulation tests (assembly and C tests)',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  Single test mode (assembly):
    %(prog)s inst_add                       # Run inst_add test once (standard mode)
    %(prog)s inst_add -c_mode               # Run inst_add in compressed mode
    %(prog)s inst_add -rwsrom -rsalu        # Run with specific variant flags
    %(prog)s inst_add -seed 12345           # Run with specific seed (for reproducibility)
    %(prog)s inst_lui -all                  # Run inst_lui with all 32 variants
    %(prog)s sandbox                        # Run sandbox test (default)

  Single test mode (C programs):
    %(prog)s hello_world                    # Run hello_world C test
    %(prog)s coremark -c_mode               # Run CoreMark with compressed instructions
    %(prog)s dhrystone_4mcu -all            # Run Dhrystone with all variants

  Information:
    %(prog)s -list                          # List all available tests

  Regression mode:
    %(prog)s -regression                    # Run one regression iteration
    %(prog)s -regression -n 5               # Run 5 regression iterations
    %(prog)s -regression --stop-on-fail     # Stop at first failing test
    %(prog)s -regression -dryrun            # Show tests that would be run
    %(prog)s -regression -list              # List enabled tests only

  RTL configuration sweep:
    %(prog)s inst_add -rtl_sweep            # Run inst_add with all RTL configurations
    %(prog)s -regression -rtl_sweep         # Run full regression with all RTL configurations
    %(prog)s -regression -rtl_sweep --stop-on-fail  # Stop at first failure
    %(prog)s -regression -rtl_config 14     # Re-run ONLY sweep config #14 (same numbering as -rtl_sweep)
    %(prog)s inst_add -rtl_config 14        # Reproduce: build config #14's RTL, run one test (dump kept; + -seed/-rsalu/-all OK)

Environment Variables:
  VERILOG_SIMULATOR : Simulator to use (iverilog [default], verilator, cver, verilog, ncverilog, vcs, vsim, isim)
  SIMULATION_NODUMP : Set to 1 to disable waveform dumping (auto-enabled in regression / -j parallel / -rtl_sweep)
        """
    )

    #====================================================================================
    # PARSE AND CHECK ARGUMENTS
    #====================================================================================

    # Test selection
    parser.add_argument('testname', nargs='*', default=['sandbox'], help='Test name(s) (default: sandbox, ignored in regression mode). Multiple names may be specified.')

    # Mode selection
    parser.add_argument('-c_mode',      action='store_true',    help='Run in compressed (16-bit) instruction mode (default: standard 32-bit mode)')
    parser.add_argument('-e_mode',      action='store_true',    help='Build the RV32E base ISA (RV32E_EN=1, ilp32e ABI, x0-x15 only). In regression only tests with requires:"RV32E_EN==1" run; all others are RV32I-only.')

    # Execution mode
    parser.add_argument('-all',         action='store_true',    help='Run all variants of the test (single test mode)')
    parser.add_argument('-regression',  action='store_true',    help='Run full regression suite with all enabled tests')
    parser.add_argument('-rtl_sweep',   action='store_true',    help='Run test(s) across the shared RTL parameterization sweep (default/corners/ofat/xprod, identical to run_lint --sweep; see bin/rtl_sweep_configs.py). Use --sweep-mode to pick a subset (default: all).')
    parser.add_argument('--sweep-mode', default='all',           help='Which sweep set to iterate when -rtl_sweep is given (one of: all, corners, ofat, xprod, default, personas). Default: all.')
    parser.add_argument('-rtl_config',  metavar='N_OR_NAME',     help='Run ONLY one sweep config. Accepts either a 1-based integer index (e.g. 14 — same numbering as -rtl_sweep) or a persona name (minimal / medium / full from bin/rtl_sweep_configs.py:PERSONAS). Re-run a single config after a sweep flagged it.')
    parser.add_argument('-n', type=int, default=1, metavar='N', help='Number of iterations (default: 1, works with -all and -regression)')
    parser.add_argument('-j', type=int, default=1, metavar='N', help='Number of parallel tests (default: 1, works with -all and -regression)')
    parser.add_argument('--stop-on-fail', action='store_true',  help='Stop after first test failure (useful with -regression or -rtl_sweep)')
    parser.add_argument('--report-show-all', action='store_true', help='Show all tests in detailed report (default: only show failures and timeouts)')

    # Variant selection (single test mode)
    parser.add_argument('-rwsrom',      action='store_true',    help='Enable random wait states on ROM')
    parser.add_argument('-wsrom',       action='store_true',    help='Enable fixed wait states on ROM')
    parser.add_argument('-rwsram',      action='store_true',    help='Enable random wait states on SRAM')
    parser.add_argument('-wssram',      action='store_true',    help='Enable fixed wait states on SRAM')
    parser.add_argument('-rwsper',      action='store_true',    help='Enable random wait states on peripherals')
    parser.add_argument('-wsper',       action='store_true',    help='Enable fixed wait states on peripherals')
    parser.add_argument('-rsalu',       action='store_true',    help='Enable random ALU stalls')
    parser.add_argument('-salu',        action='store_true',    help='Enable fixed ALU stalls')
    parser.add_argument('-gahb',        action='store_true',    help='Use generic AHB instead of high-performance AHB')
    parser.add_argument('-fahb',        action='store_true',    help='Use fused AHB interconnect (ROM/SRAM_X controllers absorbed; -rwsrom/-rwsram on SRAM_X are no-ops)')
    parser.add_argument('-rirq',        action='store_true',    help='Enable random IRQ injection')
    parser.add_argument('-ahb_check',   action='store_true',    help='Enable the AHB-Lite protocol checker (off by default; N-2 verification)')

    # Information
    parser.add_argument('-list',         action='store_true',   help='List tests (assembly and also C)')
    parser.add_argument('-list_configs', action='store_true',   help='Print the sweep set (1-based index + label) and exit. Same numbering as -rtl_sweep / -rtl_config; identical set shared with run_lint --sweep and ./run_syn -rtl_sweep/-rtl_config (single source of truth: bin/rtl_sweep_configs.py).')
    parser.add_argument('-dryrun',      action='store_true',    help='Show what would be run without executing (regression mode only)')
    # Reproducibility
    parser.add_argument('-seed',        type=int,               help='Specify random seed for reproducibility (single test mode only)')

    args = parser.parse_args()

    # Validate arguments
    if args.n < 1:
        print("Error: iterations must be >= 1", file=sys.stderr)
        return 1

    # Build variant_args list from individual flags
    variant_args = []
    if args.rwsrom:  variant_args.append('-rwsrom')
    if args.wsrom:   variant_args.append('-wsrom')
    if args.rwsram:  variant_args.append('-rwsram')
    if args.wssram:  variant_args.append('-wssram')
    if args.rwsper:  variant_args.append('-rwsper')
    if args.wsper:   variant_args.append('-wsper')
    if args.rsalu:   variant_args.append('-rsalu')
    if args.salu:    variant_args.append('-salu')
    if args.gahb:    variant_args.append('-gahb')
    if args.fahb:    variant_args.append('-fahb')
    if args.rirq:    variant_args.append('-rirq')
    if args.ahb_check: variant_args.append('-ahb_check')

    # -gahb and -fahb are mutually exclusive (different interconnect choices)
    if args.gahb and args.fahb:
        print("Error: -gahb and -fahb cannot be combined", file=sys.stderr)
        return 1

    # -e_mode pins RV32E_EN=1; -rtl_sweep / -rtl_config enumerate RTL configs and
    # would override that pinning, so the combination is unsupported.
    if args.e_mode and (args.rtl_sweep or args.rtl_config is not None):
        flag = '-rtl_sweep' if args.rtl_sweep else '-rtl_config'
        print(f"Error: -e_mode and {flag} cannot be combined", file=sys.stderr)
        return 1

    # Check for conflicting arguments
    if args.all and variant_args:
        print("Error: Cannot use -all with individual variant flags", file=sys.stderr)
        return 1

    if not args.regression and variant_args:
        # Variant flags only allowed in single test mode, not regression
        pass  # This is fine

    # -j > 1 only allowed with multiple tests or -regression
    if args.j > 1:
        if args.regression:
            pass  # OK: parallel regression
        elif args.testname and len(args.testname) > 1:
            pass  # OK: multiple tests (with or without -all)
        else:
            print("Error: -j N (parallel) only works with -regression or multiple tests", file=sys.stderr)
            return 1

    # Load configuration
    try:
        config = TestConfig()
    except (FileNotFoundError, ValueError) as e:
        print(f"Error loading configuration: {e}", file=sys.stderr)
        return 1

    # -e_mode is sugar for "pin RV32E_EN=1 for this invocation": it overrides
    # the in-memory config default (does NOT modify run_config.json on disk).
    if args.e_mode:
        try:
            config._config['rtl_config']['RV32E_EN']['default'] = 1
        except (KeyError, TypeError):
            print("Error: -e_mode requires a 'RV32E_EN' entry in run_config.json rtl_config",
                  file=sys.stderr)
            return 1

    # Derive the RV32E build from the EFFECTIVE RV32E_EN -- set either by
    # -e_mode above OR by a run_config.json default of 1 -- so RV32E_EN==1 from
    # ANY source auto-engages full e_mode behaviour. All three config consumers
    # (generate_parameterization_file, generate_march_config, _evaluate_requires)
    # already read rtl_config[...]['default'], driving the RTL build, the
    # march/ABI string (ilp32e), and the implicit RV32E_EN==0 requires-gate.
    # _e_mode additionally gates the RV32E trap-handler selection and the
    # re-run trailer; deriving it here (not from args.e_mode) keeps a single
    # source of truth and fixes the latent case where a run_config.json
    # RV32E_EN=1 would otherwise link the RV32I handler (names x28-x31) into an
    # RV32E build and fail to assemble.
    global _e_mode
    try:
        _e_mode = (int(config._config['rtl_config']['RV32E_EN']['default']) == 1)
    except (KeyError, TypeError, ValueError):
        _e_mode = False
    if _e_mode:
        print('RV32E mode: RV32E_EN=1 (ilp32e ABI); regression runs only '
              'requires:"RV32E_EN==1" tests')

    # Handle sweep-config listing BEFORE the auto-generate calls below so the
    # output is clean (no "Generated arv_parameterization.v ..." preamble).
    # Same generator/numbering/legend as run_lint --sweep, ./run_syn
    # -rtl_sweep, and ./run_syn -rtl_config N.
    if args.list_configs:
        from rtl_sweep_configs import (generate_configs, sweepable_params,
                                       print_sweep_list)
        rtl_config = config._config.get('rtl_config', {})
        _order, sweep = generate_configs(sweepable_params(rtl_config), 'all')
        print_sweep_list(sweep)
        return 0

    # Auto-generate arv_parameterization.v from run_config.json defaults
    generate_parameterization_file(config)
    generate_march_config(config, test_name=args.testname[0] if args.testname else None)

    # Handle list request
    if args.list:
        list_available_tests(config, enabled_only=args.regression)
        return 0

    # Set environment variables
    # -rtl_sweep rebuilds + reruns across the whole parameterization sweep
    # (39 configs); per-config waveforms would be huge and are never the
    # point of a sweep, so force dump/trace off just like regression/parallel.
    if args.regression or args.j > 1 or args.rtl_sweep:
        os.environ['SIMULATION_NODUMP'] = '1'   # Disable waveform dumping in regression/parallel/rtl_sweep
        # Disable trace logging in regression/parallel/rtl_sweep, but respect an explicit caller
        # override (e.g. run_benchmark sets SIMULATION_NOTRACE=0 to capture a benchmark trace with -j N)
        if os.environ.get('SIMULATION_NOTRACE') != '0':
            os.environ['SIMULATION_NOTRACE'] = '1'
    elif 'SIMULATION_NODUMP' not in os.environ:
        os.environ['SIMULATION_NODUMP'] = '0'

    if 'VERILOG_SIMULATOR' not in os.environ:
        os.environ['VERILOG_SIMULATOR'] = 'iverilog'

    # Sweep WORK/tmp* leftovers from previous invocations (failed-test dirs kept
    # by keep_on_failure=True, plus any orphans from crashed/Ctrl-C'd runs).
    # Skipped when invoked as a worker subprocess by an outer orchestrator that
    # already swept — see sweep_stale_work_dirs() docstring.
    if os.environ.get('RUNSIM_SKIP_SWEEP') != '1':
        sweep_stale_work_dirs()

    # In single-test / -all mode keep the work dir on success so the user can
    # cd into WORK/tmpXXX and inspect pmem.s, simv, traces, etc. In regression
    # mode keep only failures (current behavior) — otherwise hundreds of passing
    # dirs would accumulate during a single run. RUNSIM_NO_KEEP lets an outer
    # orchestrator (e.g. store_benchmark.py with --all) force regression-style
    # cleanup even though each subprocess is technically a "single test".
    global _keep_on_success
    _keep_on_success = (not args.regression) and (os.environ.get('RUNSIM_NO_KEEP') != '1')

    #====================================================================================
    # RTL CONFIGURATION SWEEP MODE
    #====================================================================================
    if args.rtl_sweep or args.rtl_config is not None:
        # Resolve -rtl_config: persona name OR integer index into the chosen
        # sweep mode. Persona is preferred when the token matches a known
        # persona name (bypasses the sweep-mode iteration entirely).
        from rtl_sweep_configs import PERSONAS as _PERSONAS
        _persona_names = {lbl for lbl, _ in _PERSONAS}
        sweep_mode = args.sweep_mode if args.sweep_mode else 'all'
        single_cfg = None        # 1-based index into the sweep set
        single_persona = None    # persona name string, if -rtl_config <name>
        if args.rtl_config is not None:
            if args.rtl_config in _persona_names:
                single_persona = args.rtl_config
            else:
                try:
                    single_cfg = int(args.rtl_config)
                except ValueError:
                    print(f"Error: -rtl_config '{args.rtl_config}' is neither "
                          f"an integer nor a known persona "
                          f"({sorted(_persona_names)})", file=sys.stderr)
                    return 1

        # Determine the sweep set: persona dispatch uses "personas" mode and
        # filters to the one persona; index dispatch uses --sweep-mode (default
        # 'all') and filters to one index.
        if single_persona is not None:
            sweep_mode_eff = 'personas'
        else:
            sweep_mode_eff = sweep_mode
        total_configs = config.count_rtl_config_combinations(sweep_mode_eff)

        if single_cfg is not None and not (1 <= single_cfg <= total_configs):
            print(f"Error: -rtl_config {single_cfg} out of range "
                  f"(valid: 1..{total_configs} in --sweep-mode {sweep_mode_eff})",
                  file=sys.stderr)
            return 1

        n_cfg_run = 1 if (single_cfg is not None or single_persona is not None) else total_configs

        print("=" * 70)
        print("arvern RTL Configuration Sweep")
        print("=" * 70)
        print(f"Sweep mode              : {sweep_mode_eff}")
        print(f"Total RTL configurations: {total_configs}")
        if single_persona is not None:
            print(f"Selected config         : persona '{single_persona}'")
        elif single_cfg is not None:
            sel_label = next(lbl for i, (lbl, _v)
                             in enumerate(config.get_rtl_config_combinations(sweep_mode_eff), 1)
                             if i == single_cfg)
            print(f"Selected config         : {single_cfg}/{total_configs} ({sel_label})")

        if args.regression:
            enabled_tests = config.get_enabled_tests()
            print(f"Tests enabled           : {len(enabled_tests)}")
            print(f"Total test executions   : {len(enabled_tests)} tests × 32 variants × {n_cfg_run} config(s)")
        else:
            test_display = ', '.join(args.testname)
            n_tests_sel  = len(args.testname)
            print(f"Test                    : {test_display}")
            if args.all:
                print(f"Total test executions   : 32 variants × {n_cfg_run} config(s) × {n_tests_sel} test(s)")
            else:
                print(f"Total test executions   : 1 variant × {n_cfg_run} config(s) × {n_tests_sel} test(s)")

        print("=" * 70)
        print()

        # Cleanup from previous runs. When invoked as a parallel worker by an
        # outer orchestrator (e.g. store_benchmark.py --all -j N --rtl-config X
        # spawning one runsim.py subprocess per benchmark, each in -rtl_config
        # mode), the log/ dir is SHARED across workers -- siblings' freshly-
        # written log files would get erased here, and store_benchmark.py
        # would then read an empty dir and report a spurious FAILED. Skip the
        # wipe when the orchestrator signals it owns shared state (same env
        # var used to gate the WORK/tmp* sweep at sweep_stale_work_dirs()).
        if os.environ.get('RUNSIM_SKIP_SWEEP') != '1':
            log_dir = './log'
            if os.path.exists(log_dir):
                shutil.rmtree(log_dir)

        # Track results for each RTL configuration
        config_results = []

        # Iterate through the RTL configurations in the selected sweep mode.
        # Filter FIRST -- before any param-gen / log-dir work for unselected configs.
        for config_idx, (cfg_label, rtl_values) in enumerate(config.get_rtl_config_combinations(sweep_mode_eff), 1):
            # -rtl_config N: skip every config but #N.
            if single_cfg is not None and config_idx != single_cfg:
                continue
            # -rtl_config <persona_name>: skip every config but the matching persona.
            if single_persona is not None and cfg_label != f"persona:{single_persona}":
                continue
            print(f"\n{'=' * 70}")
            print(f"RTL Configuration {config_idx}/{total_configs}: {cfg_label}")
            print(f"{'=' * 70}")

            # Print configuration
            for param_name, param_value in sorted(rtl_values.items()):
                print(f"  {param_name:15s} = {param_value}")
            print()

            # Generate arv_parameterization.v with this configuration
            generate_parameterization_file(config, rtl_values)
            generate_march_config(config, rtl_values)

            # Update _e_mode per-config so run_test_variant picks the RV32E
            # trap handler (random_irq_trap_handler_rv32e.s) when the current
            # sweep config has RV32E_EN==1. Without this, _e_mode stays at the
            # default-config value (typically False) and the RV32I trap handler
            # gets linked into RV32E builds -> assembler fails on x28-x31.
            _e_mode = (int(rtl_values.get('RV32E_EN', 0)) == 1)

            # Run test(s) with this configuration.
            #
            # Per-config log directories (`log/N-1`) keep multi-config sweeps
            # from clobbering each other. But for a SINGLE-config run
            # (-rtl_config <persona> or -rtl_config <N>), use `log/0`
            # unconditionally so the directory layout matches the regular
            # non-sweep single-test path -- store_benchmark.py reads from
            # `log/0` and would otherwise miss the only log file (a
            # successful test would be reported as "No log file found").
            if single_persona is not None or single_cfg is not None:
                iteration_log_dir = './log/0'
            else:
                iteration_log_dir = f'./log/{config_idx-1}'
            os.makedirs(iteration_log_dir, exist_ok=True)

            if args.regression:
                # Sweep iterates ALL enabled tests (incl. RV32E ones whose
                # requires:RV32E_EN==1 is excluded from get_enabled_tests by
                # the default-config requires filter). Per-config
                # check_test_requirements below applies the right gate.
                all_enabled_tests = [t for t in config.get_all_tests()
                                     if t.get('enabled', False)]
                tests_to_run = []
                tests_skipped = []

                # Filter tests based on requirements for this RTL configuration
                for test in all_enabled_tests:
                    test_name = test['name']
                    requirements_met, requires_expr = config.check_test_requirements(test_name, rtl_values)
                    if requirements_met:
                        tests_to_run.append(test)
                    else:
                        tests_skipped.append((test_name, requires_expr))

                # Report skipped tests if any
                if tests_skipped:
                    print(f"{Colors.CYAN}Skipped {len(tests_skipped)} test(s) for this RTL configuration:{Colors.NORMAL}")
                    for skip_name, skip_req in tests_skipped:
                        print(f"  - {skip_name} (requires: {skip_req})")
                    print()

                # Run tests that meet requirements
                config_test_failed = False
                n_run        = len(tests_to_run)
                n_run_w      = len(str(n_run))   # digit width of total
                max_run_name = max((len(t['name']) for t in tests_to_run), default=0)
                # Prefix: "[NNN/NNN] Running test: " — (1+w+1+w+1)+1+14 = 18 + 2*w chars
                run_indent   = 18 + 2 * n_run_w + max_run_name + 1
                # Tests within THIS RTL config; configs themselves stay
                # sequential. Each test builds its OWN work dir from this
                # config's rtl_values (custom_values=) -- without this the
                # per-test work dir would rebuild the DEFAULT parameterization
                # and the sweep would not actually vary the RTL.
                if args.j <= 1:
                    for i, test in enumerate(tests_to_run, 1):
                        test_name      = test['name']
                        test_mode      = test['mode']
                        test_toolchain = test.get('toolchain') or config._config.get('toolchain', {}).get('active', 'gcc')
                        run_pad = ' ' * (max_run_name - len(test_name))
                        print(f"[{i:{n_run_w}d}/{n_run}] Running test: {test_name}{run_pad} (mode: {test_mode}, toolchain: {test_toolchain})")
                        test_passed = run_all_variants(test_name, config, iteration_log_dir,
                                                       indent=run_indent, custom_values=rtl_values)

                        # Check if we should stop on failure
                        if args.stop_on_fail and not test_passed:
                            config_test_failed = True
                            print(f"\n{Colors.RED_BOLD}Test '{test_name}' failed. Stopping RTL sweep due to --stop-on-fail{Colors.NORMAL}\n")
                            break

                        if not test_passed:
                            config_test_failed = True
                else:
                    # Parallel tests-within-config, mirroring the proven
                    # non-sweep run_regression(jobs=N) ThreadPoolExecutor path.
                    total_modes = sum(2 if t['mode'] == 'BOTH' else 1 for t in tests_to_run)
                    sweep_start = time.time()
                    display = ParallelDisplay(total_modes, sweep_start, max_run_name)

                    def _run_one(test):
                        tn = test['name']
                        return tn, run_all_variants(tn, config, iteration_log_dir, indent=0,
                                                    custom_values=rtl_values, display=display)

                    print(f"Running {n_run} tests ({total_modes} test+mode combinations) "
                          f"with {args.j} parallel workers...")
                    print()
                    futures = {}
                    try:
                        with ThreadPoolExecutor(max_workers=args.j) as pool:
                            futures = {pool.submit(_run_one, t): t for t in tests_to_run}
                            for fut in as_completed(futures):
                                _tn, ok = fut.result()
                                if not ok:
                                    config_test_failed = True
                    except KeyboardInterrupt:
                        _cancel_event.set()
                        display.finish()
                        print(f"\n{Colors.YELLOW_BOLD}Interrupted — cancelling remaining tests...{Colors.NORMAL}")
                        for f in futures:
                            f.cancel()
                        raise
                    display.finish()

                # Store whether/how many tests were skipped for this config
                # (requires-skip: filtered out before running, so they leave
                # NO log -- invisible to parse_all_results/count_results).
                config_req_skipped = len(tests_skipped)
                config_has_skipped = config_req_skipped > 0
                requirements_met = True  # For regression, we continue even if some tests skipped
            else:
                # Check requirements and run each specified test for this RTL configuration
                config_has_skipped = False
                config_req_skipped = 0
                config_test_failed = False

                for testname in args.testname:
                    requirements_met, requires_expr = config.check_test_requirements(testname, rtl_values)

                    if requirements_met:
                        # Regenerate march_config.sh with per-test optimization level
                        generate_march_config(config, rtl_values, test_name=testname)

                        if args.all:
                            # Run all 32 variants (own work dir per test, so it
                            # must build THIS config's rtl_values, not defaults)
                            mode_override = 'COMP' if args.c_mode else None
                            test_passed = run_all_variants(testname, config, iteration_log_dir,
                                                           mode_override=mode_override, custom_values=rtl_values)
                            if not test_passed:
                                config_test_failed = True
                        else:
                            # Run single variant with specified flags (or default if none)
                            if args.c_mode:
                                mode_arg = '-c_mode'
                            else:
                                mode = config.get_test_mode(testname)
                                mode_arg = '-c_mode' if mode == 'COMP' else ''
                            # -rtl_config N is a single-test/single-config DEBUG
                            # run: tee the execution log to the console (like a
                            # plain ./run, whose log_dir=None streams to stdout)
                            # while still writing ./log/{N-1}/. j==1 here so
                            # there is no parallel output to interleave. A full
                            # -rtl_sweep over one test (39 configs) keeps tee
                            # OFF -- 39 streamed logs would bury the summary.
                            tee = (args.rtl_config is not None)
                            # Build an isolated work_dir for THIS sweep config so
                            # the flattened submit_sim.f (absolute paths) lands
                            # next to the per-config arv_parameterization.v.
                            # Without this, run_test_variant falls back to the
                            # raw bench/verilog/submit.f whose entries are bare
                            # filenames (e.g. ahb_bus_system.v) and iverilog
                            # can't find them from _run_dir.
                            sweep_work_dir = create_work_dir()
                            setup_work_dir(sweep_work_dir, config, custom_values=rtl_values, test_name=testname)
                            result = 1
                            try:
                                result = run_test_variant(testname, mode_arg, variant_args, iteration_log_dir,
                                                          seed=args.seed, tee_output=tee, work_dir=sweep_work_dir)

                                # Move asphalt.log out of the (about-to-be-deleted) work_dir
                                # to the caller's destination -- matches the non-sweep paths
                                # at run_all_variants (line ~1550) and the regular single-
                                # test path (line ~2690). Skipping this used to make ./run_
                                # benchmark --all -j N --rtl-config X silently drop 24/25
                                # traces: workers set SIMULATION_TRACE_DEST=run/asphalt_<bm>
                                # .log, but with RUNSIM_NO_KEEP=1 the work_dir (containing
                                # the only copy of asphalt.log) was deleted before anyone
                                # moved it, so the parent's _save_trace skipped silently.
                                if os.environ.get('SIMULATION_NOTRACE') != '1':
                                    trace_dest = os.environ.get('SIMULATION_TRACE_DEST')
                                    if trace_dest:
                                        work_trace = os.path.join(sweep_work_dir, 'asphalt.log')
                                        if os.path.exists(work_trace):
                                            shutil.move(work_trace, trace_dest)
                            finally:
                                cleanup_work_dir(sweep_work_dir, keep_on_failure=True, failed=(result != 0))
                            if result != 0:
                                config_test_failed = True
                    else:
                        # Skip test - requirements not met for this RTL configuration
                        print(f"{Colors.CYAN}Test '{testname}' skipped for this RTL configuration{Colors.NORMAL}")
                        print(f"{Colors.CYAN}Required: {requires_expr}{Colors.NORMAL}")
                        print()
                        config_has_skipped = True
                        config_req_skipped += 1

            # Parse results for this configuration. NOTE: requires-skipped
            # tests leave no log, so they are absent from `results` /
            # `counts` entirely -- only `config_req_skipped` records them.
            # counts['SKIPPED'] is a *runtime* self-skip (a ran test whose
            # log says SKIPPED); structurally 0 here -- no testbench emits
            # 'SKIPPED' -- kept only for the parse_results status contract.
            results = parse_all_results(iteration_log_dir)
            counts = count_results(results)
            total_tests = len(results)

            # Determine if all tests were skipped due to requirements
            all_tests_skipped = (total_tests == 0 and config_has_skipped)

            config_results.append({
                'config_idx': config_idx,
                'rtl_values': rtl_values,
                'results': results,
                'counts': counts,
                'skipped': all_tests_skipped,
                'has_skipped': config_has_skipped,
                'req_skipped': config_req_skipped
            })

            # Print summary for this configuration. A TIMEOUT is a failure
            # (hung / livelocked test), same as the regression summary
            # semantics: clean iff FAILED + TIMEOUT + ABORTED == 0.
            passed = counts['PASSED']
            failed = counts['FAILED'] + counts['TIMEOUT'] + counts['ABORTED']

            if all_tests_skipped:
                status = f"{Colors.CYAN}SKIPPED{Colors.NORMAL}"
                print(f"\nConfiguration {config_idx} Result: all {config_req_skipped} test(s) skipped (requirements not met)\n")
            else:
                status = f"{Colors.GREEN_BOLD}ALL PASSED{Colors.NORMAL}" if failed == 0 else f"{Colors.RED_BOLD}FAILED{Colors.NORMAL}"
                skip_note = f" (+{config_req_skipped} skipped)" if config_req_skipped else ""
                print(f"\nConfiguration {config_idx} Result: {passed}/{total_tests} passed{skip_note} {status}\n")

            # Check if we should stop on failure
            if args.stop_on_fail and config_test_failed:
                print(f"{Colors.RED_BOLD}Stopping RTL sweep due to test failures (--stop-on-fail){Colors.NORMAL}\n")
                break

        # Print final summary
        print("\n" + "=" * 70)
        print("RTL Sweep Summary")
        print("=" * 70)
        print()

        for entry in config_results:
            config_idx = entry['config_idx']
            counts = entry['counts']
            skipped = entry.get('skipped', False)
            # requires-skipped count: tests filtered out before running, so
            # they are NOT in counts/total_tests -- surfaced as coverage info
            # so a partial run can't masquerade as a full PASS.
            req_skipped = entry.get('req_skipped', 0)
            skip_note = f" (+{req_skipped} skipped)" if req_skipped else ""
            total_tests = sum(counts.values())
            passed = counts['PASSED']
            n_fail, n_to, n_ab = counts['FAILED'], counts['TIMEOUT'], counts['ABORTED']
            failed = n_fail + n_to + n_ab   # TIMEOUT counts as failure

            if skipped:
                status = f"{Colors.CYAN}SKIP{Colors.NORMAL}"
                result_str = f"all {req_skipped} skipped"
            elif failed == 0:
                status = f"{Colors.GREEN_BOLD}PASS{Colors.NORMAL}"
                result_str = f"{passed}/{total_tests} passed{skip_note}"
            else:
                status = f"{Colors.RED_BOLD}FAIL{Colors.NORMAL}"
                brk = ", ".join(s for s in (
                    f"{n_fail} failed"  if n_fail else "",
                    f"{n_to} timeout"   if n_to   else "",
                    f"{n_ab} aborted"   if n_ab   else "") if s)
                result_str = f"{passed}/{total_tests} passed ({brk}){skip_note}"

            config_str = ", ".join(f"{k}={v}" for k, v in sorted(entry['rtl_values'].items()))
            # Status tag first (PASS/FAIL/SKIP are all 4 chars -> [..] is a
            # fixed 6-col field, self-aligning). result_str is plain text
            # (no color codes) so <30 left-justify aligns the ' - <params>'
            # column for the dominant PASS/SKIP rows; longer FAIL rows
            # overflow (the only ragged minority, vs. all rows before).
            print(f"Config {config_idx:3d}: [{status}] {result_str:<30s} - {config_str}")

        print()
        print("=" * 70)
        print("RTL Sweep complete!")
        print("=" * 70)

        # Restore default configuration
        generate_parameterization_file(config, None)
        generate_march_config(config, None)

        return 0

    #====================================================================================
    # REGRESSION MODE
    #====================================================================================
    if args.regression:
        enabled_tests = config.get_enabled_tests()

        # Handle dry-run
        if args.dryrun:
            print(f"\nEnabled tests ({len(enabled_tests)}):")
            for test in enabled_tests:
                print(f"  {test['name']:20s} {test['mode']:8s} - {test['description']}")
            print(f"\nWould run {args.n} regression iteration(s)")
            if variant_args:
                num_variants = 1
                variant_note = f" (variant: {' '.join(variant_args)})"
            else:
                num_variants = len(get_test_variants())
                variant_note = " (single variant mode)" if num_variants == 1 else ""
            print(f"Total test executions: {len(enabled_tests)} tests × {num_variants} variant(s) × {args.n} iterations{variant_note}")
            return 0

        # Print regression header
        print("=" * 70)
        print("arvern Regression Suite")
        print("=" * 70)
        print(f"Simulator       : {os.environ['VERILOG_SIMULATOR']}")
        print(f"Waveform dumping: disabled")
        print(f"Iterations      : {args.n}")
        print(f"Tests enabled   : {len(enabled_tests)}")
        if variant_args:
            print(f"Variant         : {' '.join(variant_args)}")
        if args.j > 1:
            print(f"Parallel workers: {args.j}")
        print("=" * 70)

        # Cleanup from previous regression
        log_dir = './log'
        if os.path.exists(log_dir):
            shutil.rmtree(log_dir)

        # Run regression iterations
        regression_passed = True
        for iteration in range(args.n):
            iteration_passed = run_regression(iteration, config, args.stop_on_fail, args.report_show_all, jobs=args.j,
                                              variant_args=variant_args if variant_args else None)
            if not iteration_passed:
                regression_passed = False
                if args.stop_on_fail:
                    print(f"\n{Colors.RED_BOLD}Stopping regression due to failures in iteration {iteration} (--stop-on-fail){Colors.NORMAL}")
                    break

        # Parse summaries if multiple iterations
        if args.n > 1:
            print("\n" + "=" * 70)
            print("Parsing regression summaries...")
            print("=" * 70 + "\n")

            # Find all summary files
            summary_files = sorted(Path(log_dir).glob('summary.*.log'))
            summary_files = [str(f) for f in summary_files]

            if summary_files:
                print(f"\nFound {len(summary_files)} summary file(s)")

                # Aggregate results
                test_stats, overall_counts = parse_summaries.aggregate_results(summary_files)

                # Write to summary log file
                summary_log = f'{log_dir}/../regressions_summary.log'
                with open(summary_log, 'w') as f:
                    # Redirect stdout to file temporarily
                    old_stdout = sys.stdout
                    sys.stdout = f
                    try:
                        parse_summaries.print_detailed_report(test_stats, show_all=args.report_show_all)
                        parse_summaries.print_failing_regressions(log_dir)
                        parse_summaries.print_summary_report(overall_counts, log_dir)
                    finally:
                        sys.stdout = old_stdout

                # Also print to stdout
                parse_summaries.print_detailed_report(test_stats, show_all=args.report_show_all)
                parse_summaries.print_failing_regressions(log_dir)
                parse_summaries.print_summary_report(overall_counts, log_dir)

        print("\n" + "=" * 70)
        print("Regression complete!")
        print("=" * 70)

        # Return non-zero if any tests failed
        return 0 if regression_passed else 1

    #====================================================================================
    # SINGLE TEST MODE
    #====================================================================================

    # Verify all specified tests exist and meet requirements
    testnames = args.testname

    # Expand wildcard patterns (e.g. inst_zcmp_*) and remove duplicates.
    # Note: quote wildcards in fish shell to prevent shell expansion, e.g. "./run 'inst_zcmp_*' -all"
    _src_dir   = os.path.join(_run_dir, '..', 'src')
    _src_c_dir = os.path.join(_run_dir, '..', 'src-c')
    available_asm  = sorted(p.stem for p in Path(_src_dir).glob("*.v"))
    available_c    = sorted(d.name for d in Path(_src_c_dir).iterdir() if d.is_dir())
    available_all  = available_asm + available_c
    expanded: list = []
    for pattern in testnames:
        if any(c in pattern for c in ('*', '?', '[')):
            matches = [t for t in available_all if fnmatch.fnmatch(t, pattern)]
            if not matches:
                print(f"{Colors.YELLOW}[WARNING] No tests match wildcard '{pattern}'{Colors.NORMAL}", file=sys.stderr)
            expanded.extend(matches)
        else:
            expanded.append(pattern)
    seen: set = set()
    testnames = []
    for t in expanded:
        if t not in seen:
            seen.add(t)
            testnames.append(t)
    n_dupes = len(expanded) - len(testnames)
    if n_dupes > 0:
        print(f"{Colors.CYAN}[INFO] Removed {n_dupes} duplicate test name(s){Colors.NORMAL}", flush=True)

    all_tests = config.get_all_tests()
    test_names = {test['name'] for test in all_tests}

    for testname in testnames:
        test_type = detect_test_type(testname)
        if test_type is None:
            print(f"[ERROR] Test '{testname}' not found in ../src/ or ../src-c/", file=sys.stderr)
            print()
            print("Available assembly tests (../src/):")
            for test_file in sorted(Path(_src_dir).glob("*.v")):
                tn = test_file.stem
                print(f"  {tn}")
            print()
            print("Available C tests (../src-c/):")
            for test_dir in sorted(Path(_src_c_dir).iterdir()):
                if test_dir.is_dir():
                    print(f"  {test_dir.name}")
            suggestions = difflib.get_close_matches(testname, available_all, n=3, cutoff=0.5)
            if suggestions:
                print(f"\n{Colors.CYAN}Did you mean: {', '.join(suggestions)} ?{Colors.NORMAL}", flush=True)
            return 1

        if testname not in test_names:
            print(f"{Colors.CYAN}[INFO] Test '{testname}' is not registered in run_config.json{Colors.NORMAL}")
            print(f"{Colors.CYAN}[INFO] Running with default configuration (standard mode){Colors.NORMAL}")
            print()
        else:
            # Check test requirements
            requirements_met, requires_expr = config.check_test_requirements(testname)
            if not requirements_met:
                print(f"{Colors.RED}[ERROR] Test '{testname}' cannot run with current RTL configuration{Colors.NORMAL}")
                print(f"{Colors.RED}[ERROR] Required: {requires_expr}{Colors.NORMAL}")
                print(f"{Colors.CYAN}[INFO] Update run_config.json rtl_config section to meet requirements{Colors.NORMAL}")
                return 1

    # Run test with all variants
    if args.all:
        # Check if -c_mode was specified and validate C_EXTENSION is enabled
        mode_override = None
        if args.c_mode:
            rtl_config = config.get_rtl_config()
            c_ext_enabled = rtl_config.get('C_EXTENSION', {}).get('default', 0)
            if c_ext_enabled == 0:
                print(f"{Colors.RED}Error: -c_mode requires C_EXTENSION>=1 in RTL configuration{Colors.NORMAL}", file=sys.stderr)
                print(f"Current RTL configuration has C_EXTENSION={c_ext_enabled}", file=sys.stderr)
                print(f"Please enable C extension in run_config.json or use -rtl_sweep to test all configurations", file=sys.stderr)
                return 1
            mode_override = 'COMP'

        # Cleanup from previous runs
        log_dir = './log'
        if os.path.exists(log_dir):
            shutil.rmtree(log_dir)

        # Print header if multiple iterations or multiple tests
        n_tests = len(testnames)
        if args.n > 1 or n_tests > 1:
            print("=" * 70)
            if n_tests == 1:
                print(f"Running test '{testnames[0]}' with all variants")
            else:
                print(f"Running {n_tests} tests with all variants: {', '.join(testnames)}")
            if mode_override:
                print(f"Mode            : COMPRESSED (overriding test configuration)")
            print("=" * 70)
            print(f"Tests           : {n_tests}")
            print(f"Iterations      : {args.n}")
            print(f"Variants        : 32")
            print(f"Total executions: {32 * args.n * n_tests}")
            print("=" * 70)
            print()

        # Pre-compute alignment constants for consistent column alignment (same as regression)
        n_tests_w    = len(str(n_tests))
        max_name_len = max(len(t) for t in testnames)
        # Prefix: "[MM:SS] [NNN/NNN] Running test: " — 7+1+(1+w+1+w+1)+1+14 = 26 + 2*w chars
        sub_indent   = 26 + 2 * n_tests_w + max_name_len + 1
        all_start_time = time.time()

        # Run iterations
        for iteration in range(args.n):
            if args.n > 1:
                print(f"\n{'=' * 70}")
                print(f"Iteration {iteration + 1}/{args.n}")
                print(f"{'=' * 70}\n")

            iteration_log_dir = f'./log/{iteration}'
            os.makedirs(iteration_log_dir, exist_ok=True)

            # Run all tests for this iteration
            if args.j > 1 and n_tests > 1:
                # Parallel mode with ParallelDisplay
                total_modes = sum(2 if (mode_override or config.get_test_mode(tn)) == 'BOTH' else 1 for tn in testnames)
                display = ParallelDisplay(total_modes, all_start_time, max_name_len)

                def run_test_all_parallel(testname):
                    return testname, run_all_variants(testname, config, iteration_log_dir, mode_override=mode_override, indent=0, display=display)

                print(f"Running {n_tests} tests with {args.j} parallel workers...")
                print()

                # Pre-bind before the try so an early KeyboardInterrupt
                # can't NameError in the except cancel loop.
                futures = {}
                try:
                    with ThreadPoolExecutor(max_workers=args.j) as pool:
                        futures = {pool.submit(run_test_all_parallel, tn): tn for tn in testnames}
                        for future in as_completed(futures):
                            testname, test_passed = future.result()
                            if not test_passed:
                                pass  # failure tracking handled by results parsing below
                except KeyboardInterrupt:
                    _cancel_event.set()
                    display.finish()
                    print(f"\n{Colors.YELLOW_BOLD}Interrupted — cancelling remaining tests...{Colors.NORMAL}")
                    for f in futures:
                        f.cancel()
                    return 1

                display.finish()
            else:
                # Sequential mode
                for i, testname in enumerate(testnames, 1):
                    if n_tests > 1:
                        elapsed  = int(time.time() - all_start_time)
                        ts       = f"{elapsed // 60:02d}:{elapsed % 60:02d}"
                        tmode    = mode_override if mode_override else config.get_test_mode(testname)
                        pad      = ' ' * (max_name_len - len(testname))
                        print(f"[{ts}] [{i:{n_tests_w}d}/{n_tests}] Running test: {Colors.CYAN}{Colors.BOLD}{testname}{Colors.NORMAL}{pad} (mode: {tmode})")
                        run_all_variants(testname, config, iteration_log_dir, mode_override=mode_override, indent=sub_indent)
                    else:
                        run_all_variants(testname, config, iteration_log_dir, mode_override=mode_override)

            # Parse all results for this iteration
            results = parse_all_results(iteration_log_dir)

            if args.n > 1 or n_tests > 1:
                # Show brief summary per iteration
                counts = count_results(results)
                status = f"{Colors.GREEN_BOLD}[PASS]{Colors.NORMAL}" if counts['FAILED'] + counts['TIMEOUT'] + counts['ABORTED'] == 0 else f"{Colors.RED_BOLD}[FAIL]{Colors.NORMAL}"
                print(f"\nIteration {iteration + 1} summary: {counts['PASSED']} passed, {counts['FAILED']} failed, {Colors.YELLOW_BOLD}{counts['TIMEOUT']} timeout{Colors.NORMAL}, {Colors.VIOLET_BOLD}{counts['ABORTED']} aborted{Colors.NORMAL} {status}")
            else:
                # Single iteration, single test: show detailed reports
                print_detailed_report(results, show_all=args.report_show_all)
                print_skipped_failed_tests(results)

                # Print benchmark statistics if this is a benchmark test
                if config.is_benchmark(testnames[0]):
                    metric_name = config.get_benchmark_metric(testnames[0])
                    print_benchmark_statistics(results, metric_name)

                print_summary_report(results)

        # Aggregate across iterations/tests when needed
        if args.n > 1 or n_tests > 1:
            print("\n" + "=" * 70)
            print("Parsing all iteration summaries...")
            print("=" * 70 + "\n")

            all_results = []
            for iteration in range(args.n):
                iteration_log_dir = f'./log/{iteration}'
                results = parse_all_results(iteration_log_dir)
                all_results.extend(results)

            # Show aggregated detailed report
            print_detailed_report(all_results, show_all=args.report_show_all)
            print_skipped_failed_tests(all_results)

            # Print benchmark statistics if a single benchmark test was run
            if n_tests == 1 and config.is_benchmark(testnames[0]):
                metric_name = config.get_benchmark_metric(testnames[0])
                print_benchmark_statistics(all_results, metric_name)

            print_summary_report(all_results)

        # Note: --stop-on-fail has no effect in single test mode (all variants already ran)
        # It's only useful for regression mode and RTL sweep mode
        return 0

    # Warn if -rirq is used on a test that disables random IRQ injection
    if '-rirq' in variant_args:
        for testname in testnames:
            if config.is_no_random_irq(testname):
                print(f"{Colors.YELLOW}Warning: Test '{testname}' has no_random_irq=true, -rirq flag will be ignored{Colors.NORMAL}")
                variant_args = [v for v in variant_args if v != '-rirq']
                break

    # Check C extension early if needed
    if args.c_mode:
        rtl_config = config.get_rtl_config()
        c_ext_enabled = rtl_config.get('C_EXTENSION', {}).get('default', 0)
        if c_ext_enabled == 0:
            print(f"{Colors.RED}Error: -c_mode requires C_EXTENSION>=1 in RTL configuration{Colors.NORMAL}", file=sys.stderr)
            print(f"Current RTL configuration has C_EXTENSION={c_ext_enabled}", file=sys.stderr)
            print(f"Please enable C extension in run_config.json or use -rtl_sweep to test all configurations", file=sys.stderr)
            return 1

    def run_single_test(testname):
        """Run a single test (one variant). Returns (testname, exit_code)."""
        is_benchmark_test = config.is_benchmark(testname)
        log_dir = None
        tee_output = False
        if is_benchmark_test:
            log_dir = './log/0'
            os.makedirs(log_dir, exist_ok=True)
            tee_output = True

        # Determine mode
        if args.c_mode:
            mode_arg = '-c_mode'
        else:
            mode = config.get_test_mode(testname)
            mode_arg = '-c_mode' if mode == 'COMP' else ''
            if mode == 'COMP':
                rtl_config = config.get_rtl_config()
                c_ext_enabled = rtl_config.get('C_EXTENSION', {}).get('default', 0)
                if c_ext_enabled == 0:
                    with _print_lock:
                        print(f"{Colors.RED}Error: Test '{testname}' requires COMP mode but C_EXTENSION=0{Colors.NORMAL}", file=sys.stderr)
                    return testname, 1

        # Always create an isolated work directory — ensures each run (including
        # concurrent calls from run_benchmark -j N) gets its own pmem.ihex, symlinks,
        # checker_data.mem, and simulation outputs instead of clobbering run/.
        work_dir = create_work_dir()
        setup_work_dir(work_dir, config, test_name=testname)

        result = 1  # assume failure until proven otherwise
        try:
            result = run_test_variant(testname, mode_arg, variant_args, log_dir, seed=args.seed, tee_output=tee_output, work_dir=work_dir)

            # Default-named asphalt.log and the VCD are exposed via symlinks
            # (created in setup_work_dir). Only the per-benchmark trace dest
            # still needs an explicit move out of the work dir.
            if os.environ.get('SIMULATION_NOTRACE') != '1':
                trace_dest = os.environ.get('SIMULATION_TRACE_DEST')
                if trace_dest:
                    work_trace = os.path.join(work_dir, 'asphalt.log')
                    if os.path.exists(work_trace):
                        shutil.move(work_trace, trace_dest)
        finally:
            cleanup_work_dir(work_dir, keep_on_failure=True, failed=(result != 0))

        # If benchmark test, extract and display score
        if is_benchmark_test and log_dir:
            # Identify current run's log and extract its score
            mode_suffix = '-c' if mode_arg == '-c_mode' else '-std'
            suffix = get_variant_log_suffix(variant_args)
            current_log = os.path.join(log_dir, f"{testname}{mode_suffix}{suffix}.log")
            current_score = None
            if os.path.exists(current_log):
                benchmark_pattern = config.get_benchmark_pattern(testname)
                cur = parse_log_file(current_log, benchmark_pattern)
                if cur.score is not None and cur.status == 'PASSED':
                    current_score = cur.score

            results = parse_all_results(log_dir, testname, config)
            if results:
                metric_name = config.get_benchmark_metric(testname)
                print_benchmark_statistics(results, metric_name, current_score=current_score)
            else:
                print(f"\n{Colors.VIOLET}Warning: No log files found in {log_dir}{Colors.NORMAL}")

        return testname, result

    # Run single variant for each specified test
    overall_result = 0
    n_tests = len(testnames)

    if args.j > 1 and n_tests > 1:
        # Parallel mode
        print(f"Running {n_tests} tests with {args.j} parallel workers...")
        print()
        start_time = time.time()

        # Pre-bind before the try so an early KeyboardInterrupt (even before
        # the comprehension) can't NameError in the except cancel loop.
        futures = {}
        try:
            with ThreadPoolExecutor(max_workers=args.j) as pool:
                futures = {pool.submit(run_single_test, tn): tn for tn in testnames}
                completed = 0
                for future in as_completed(futures):
                    testname, result = future.result()
                    completed += 1
                    with _print_lock:
                        elapsed = int(time.time() - start_time)
                        ts = f"{elapsed // 60:02d}:{elapsed % 60:02d}"
                        status = f"{Colors.GREEN_BOLD}[PASS]{Colors.NORMAL}" if result == 0 else f"{Colors.RED_BOLD}[FAIL]{Colors.NORMAL}"
                        print(f"[{ts}] [{completed}/{n_tests}] {testname} {status}")
                    if result != 0:
                        overall_result = result
        except KeyboardInterrupt:
            _cancel_event.set()
            print(f"\n{Colors.YELLOW_BOLD}Interrupted — cancelling remaining tests...{Colors.NORMAL}")
            for f in futures:
                f.cancel()
            return 1
    else:
        # Sequential mode
        for testname in testnames:
            _, result = run_single_test(testname)
            if result != 0:
                overall_result = result

    return overall_result


if __name__ == '__main__':
    sys.exit(main())
