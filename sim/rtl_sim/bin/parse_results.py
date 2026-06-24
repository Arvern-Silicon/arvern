#!/usr/bin/env python3
#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Script:    parse_results.py
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Aggregate per-test simulation log output into a regression summary.
#----------------------------------------------------------------------------

"""
Parse regression test results from log files.

This module provides both a command-line tool for detailed result reporting
and a programmatic API for use by other scripts (like runsim.py).
"""

import os
import sys
import re
from pathlib import Path
from dataclasses import dataclass
from typing import Dict, List, Tuple, Optional


@dataclass
class TestResult:
    """Represents the result of a single test variant."""
    testname:       str
    status:         str   # 'PASSED', 'FAILED', 'SKIPPED', 'ABORTED', 'TIMEOUT'
    log_file:       str
    seed:           str            = ""
    replay_command: str            = ""
    score:          Optional[float] = None  # Benchmark score if test is a benchmark


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


def parse_log_file(log_file: str, benchmark_pattern: Optional[str] = None) -> TestResult:
    """
    Parse a single log file to determine test status and optionally extract benchmark score.

    Args:
        log_file: Path to the log file
        benchmark_pattern: Optional regex pattern to extract score (first capture group)

    Returns:
        TestResult object with parsed information
    """
    testname = Path(log_file).stem  # Get filename without extension

    # Extract seed from log file
    seed = ""
    score = None
    try:
        with open(log_file, 'r') as f:
            for line in f:
                if 'SIMULATION SEED' in line:
                    # Extract seed number from line like "SIMULATION SEED: 12345" or "SIMULATION SEED = 12345"
                    match = re.search(r'SIMULATION SEED\s*[=:]\s*(\d+)', line)
                    if match:
                        seed = match.group(1)
                    break
    except Exception:
        pass

    # Determine test status and extract benchmark score
    status = 'ABORTED'  # Default
    try:
        with open(log_file, 'r') as f:
            content = f.read()
            # Check for timeout first (most specific)
            # Format: "SIMULATION FAILED" with "(simulation Timeout)"
            if 'simulation Timeout' in content or 'TIMEOUT' in content:
                status = 'TIMEOUT'
            elif 'PASSED' in content:
                status = 'PASSED'
            elif 'SKIPPED' in content:
                status = 'SKIPPED'
            elif 'FAILED' in content:
                status = 'FAILED'
            # Otherwise remains ABORTED (includes incomplete/crashed tests)

            # Extract benchmark score if pattern provided
            if benchmark_pattern and status == 'PASSED':
                try:
                    score_match = re.search(benchmark_pattern, content)
                    if score_match:
                        score = float(score_match.group(1))
                    else:
                        # Warn if pattern doesn't match in a passing benchmark test
                        print(f"{Colors.YELLOW}Warning: Benchmark pattern '{benchmark_pattern}' did not match in {log_file}{Colors.NORMAL}")
                except (ValueError, IndexError) as e:
                    print(f"{Colors.YELLOW}Warning: Failed to extract score from {log_file}: {e}{Colors.NORMAL}")
    except Exception:
        pass

    # Build replay command by parsing testname
    replay_args = []
    clean_testname = testname

    # Parse test name to extract variant flags
    # Expected format: testname-std-<variants> or testname-c-<variants>
    mode_arg = ""

    # Log file stem format: {base_name}-{mode}[-{flag1}-{flag2}...]
    # Each flag token mirrors its argument name (leading '-' stripped).
    base_name = clean_testname.split('-')[0]
    if clean_testname.startswith(base_name + '-std-'):
        mode_arg   = ""
        suffix_str = clean_testname[len(base_name) + len('-std-'):]
    elif clean_testname == base_name + '-std':
        mode_arg   = ""
        suffix_str = ''
    elif clean_testname.startswith(base_name + '-c-'):
        mode_arg   = '-c_mode'
        suffix_str = clean_testname[len(base_name) + len('-c-'):]
    elif clean_testname == base_name + '-c':
        mode_arg   = '-c_mode'
        suffix_str = ''
    else:
        suffix_str = ''

    # Each token maps directly to its argument (token == arg without leading '-')
    known_flags = {
        'gahb':   '-gahb',
        'rwsrom': '-rwsrom',  'wsrom':  '-wsrom',
        'rwsram': '-rwsram',  'wssram': '-wssram',
        'rwsper': '-rwsper',  'wsper':  '-wsper',
        'rsalu':  '-rsalu',   'salu':   '-salu',
        'rirq':   '-rirq',
    }
    for token in [t for t in suffix_str.split('-') if t]:
        if token in known_flags:
            replay_args.append(known_flags[token])
    clean_testname = base_name

    # Build complete replay command
    replay_parts = ['./run']
    replay_parts.append(clean_testname)
    if mode_arg:
        replay_parts.append(mode_arg)
    replay_parts.extend(replay_args)
    if seed:
        replay_parts.append(f'-seed {seed}')

    replay_command = ' '.join(replay_parts)

    return TestResult(
        testname=testname,
        status=status,
        log_file=log_file,
        seed=seed,
        replay_command=replay_command,
        score=score
    )


def parse_all_results(log_dir: str, test_name: Optional[str] = None, config=None) -> List[TestResult]:
    """
    Parse all log files in a directory.

    Args:
        log_dir: Directory containing log files
        test_name: Optional test name to check if it's a benchmark
        config: Optional TestConfig instance for benchmark info

    Returns:
        List of TestResult objects
    """
    results = []

    # Determine if this test is a benchmark and get the pattern
    benchmark_pattern = None
    if test_name and config:
        # Extract base test name (remove variant suffixes)
        base_test_name = test_name.split('-')[0]
        if config.is_benchmark(base_test_name):
            benchmark_pattern = config.get_benchmark_pattern(base_test_name)

    # Find all .log files
    log_files = sorted(Path(log_dir).glob('*.log'))

    # Derive the base test name once (used to scope benchmark_pattern to matching logs only)
    base_test_name = test_name.split('-')[0] if test_name else None

    for log_file in log_files:
        # Only apply benchmark_pattern to logs that belong to this benchmark test;
        # other logs in the directory (from previous runs) must not trigger the warning.
        log_base = log_file.stem.split('-')[0]
        scoped_pattern = benchmark_pattern if (base_test_name and log_base == base_test_name) else None
        results.append(parse_log_file(str(log_file), scoped_pattern))

    return results


def count_results(results: List[TestResult]) -> Dict[str, int]:
    """
    Count test results by status.

    Args:
        results: List of TestResult objects

    Returns:
        Dictionary with counts for each status
    """
    counts = {
        'PASSED': 0,
        'SKIPPED': 0,
        'FAILED': 0,
        'TIMEOUT': 0,
        'ABORTED': 0
    }

    for result in results:
        counts[result.status] = counts.get(result.status, 0) + 1

    return counts


def print_detailed_report(results: List[TestResult], show_all: bool = False):
    """Print detailed test results table.

    Args:
        results: List of TestResult objects
        show_all: If True, show all tests. If False, only show failures and timeouts (default)
    """
    # Filter results if show_all is False
    if not show_all:
        filtered_results = [r for r in results if r.status in ('FAILED', 'TIMEOUT', 'ABORTED')]
        if not filtered_results:
            # No failures or timeouts to show
            print()
            print("#" + "=" * 67 + "#")
            print("#" + " " * 20 + "DETAILED REPORT" + " " * 32 + "#")
            print("#" + "=" * 67 + "#")
            print()
            print(f"         {Colors.GREEN_BOLD}All tests passed!{Colors.NORMAL}")
            print(f"         Use --report-show-all to see all test results")
            print()
            return
    else:
        filtered_results = results

    print()
    print("#" + "=" * 191 + "#")
    print("#" + " " * 191 + "#")
    header_text = "DETAILED REPORT" if show_all else "DETAILED REPORT (FAILURES & TIMEOUTS ONLY)"
    padding = (191 - len(header_text)) // 2
    print("#" + " " * padding + header_text + " " * (191 - padding - len(header_text)) + "#")
    print("#" + " " * 191 + "#")
    print("#" + "=" * 191 + "#")
    print("#" + " " * 18 + "||" + " " * 6 + "||" + " " * 11 + "||" + " " * 88 + "||" + " " * 60 + "#")
    print("#" + "  TEST NAME" + " " * 7 + "||" + " MODE " + "||" + "  RESULT  " + " " + "||" + " " * 34 + "REPLAY COMMAND" + " " * 40 + "||" + " " * 26 + "LOG FILE" + " " * 26 + "#")
    print("#" + " " * 18 + "||" + " " * 6 + "||" + " " * 11 + "||" + " " * 88 + "||" + " " * 60 + "#")
    print("#" + "=" * 18 + "++" + "=" * 6 + "++" + "=" * 11 + "++" + "=" * 88 + "++" + "=" * 60 + "#")
    print("#" + " " * 18 + "||" + " " * 6 + "||" + " " * 11 + "||" + " " * 88 + "||" + " " * 60 + "#")

    for result in filtered_results:
        # Extract base test name and mode from full testname
        full_name = result.testname

        # Expected format: testname-std-<variants> or testname-c-<variants>
        parts = full_name.split('-')
        if len(parts) >= 2 and parts[1] == 'std':
            mode = 'STD'
            base_name = parts[0]
        elif len(parts) >= 2 and parts[1] == 'c':
            mode = 'COMP'
            base_name = parts[0]
        else:
            # Default to standard mode if format is unclear
            mode = 'STD'
            base_name = parts[0]

        # Format status with color (status column is 11 chars: " " + status(9) + " ")
        if result.status == 'PASSED':
            status_str = f"{Colors.GREEN} PASSED  {Colors.NORMAL}"  # 9 visible chars
            replay_color = Colors.NORMAL
        elif result.status == 'SKIPPED':
            status_str = f"{Colors.NORMAL} SKIPPED {Colors.NORMAL}"  # 9 visible chars
            replay_color = Colors.NORMAL
        elif result.status == 'FAILED':
            status_str = f"{Colors.RED} FAILED  {Colors.NORMAL}"  # 9 visible chars
            replay_color = Colors.RED
        elif result.status == 'TIMEOUT':
            status_str = f"{Colors.YELLOW} TIMEOUT {Colors.NORMAL}"  # 9 visible chars (7 letters + 2 spaces)
            replay_color = Colors.YELLOW
        else:  # ABORTED
            status_str = f"{Colors.VIOLET} ABORTED {Colors.NORMAL}"  # 9 visible chars
            replay_color = Colors.VIOLET

        # Format log file (show full path, truncate if needed) - 48 chars wide
        log_str = './'+result.log_file
        if len(log_str) > 48:
            log_str = "..." + log_str[-45:]

        # Format replay command (truncate if too long) - replay column is 88 chars: " " + replay(86) + " "
        replay_str = result.replay_command
        if len(replay_str) > 86:
            replay_str = replay_str[:83] + "..."

        print(f"#  {base_name:<15s} || {mode:^4s} || {status_str} || {replay_color}{replay_str:<86s}{Colors.NORMAL} || {log_str:<58s} #")

    print("#" + " " * 18 + "||" + " " * 6 + "||" + " " * 11 + "||" + " " * 88 + "||" + " " * 60 + "#")
    print("#" + "=" * 191 + "#")
    print()



def print_skipped_failed_tests(results: List[TestResult]):
    """Print list of skipped, failed, timeout, and aborted tests."""
    # Collect all problem categories
    skipped = [r for r in results if r.status == 'SKIPPED']
    failed = [r for r in results if r.status == 'FAILED']
    timeout = [r for r in results if r.status == 'TIMEOUT']
    aborted = [r for r in results if r.status == 'ABORTED']

    # Skip this entire section if there are no failures, timeouts, or aborted tests
    if not failed and not timeout and not aborted:
        return

    print()
    print("#" + "=" * 67 + "#")
    print("#" + " " * 18 + "SKIPPED, FAILED, TIMEOUT & ABORTED" + " " * 15 + "#")
    print("#" + "=" * 67 + "#")
    print()

    # Print skipped tests
    if skipped:
        print(" SKIPPED TESTS:")
        for result in skipped:
            print(f"                 -  {result.log_file}")
    print()

    # Print failed tests
    if failed:
        print(f"{Colors.RED_BOLD} FAILED TESTS:{Colors.NORMAL}")
        for result in failed:
            print(f"{Colors.RED_BOLD}                 -  {result.log_file}{Colors.NORMAL}")
    print()

    # Print timeout tests
    if timeout:
        print(f"{Colors.YELLOW_BOLD} TIMEOUT TESTS:{Colors.NORMAL}")
        for result in timeout:
            print(f"{Colors.YELLOW_BOLD}                 -  {result.log_file}{Colors.NORMAL}")
    print()

    # Print aborted tests
    if aborted:
        print(f"{Colors.VIOLET_BOLD} ABORTED TESTS:{Colors.NORMAL}")
        for result in aborted:
            print(f"{Colors.VIOLET_BOLD}                 -  {result.log_file}{Colors.NORMAL}")
    print()



def print_rtl_config(rtl_config: Dict):
    """
    Print the RTL configuration used for the regression.

    Args:
        rtl_config: Dictionary of RTL configuration parameters
    """
    print()
    print("#" + "=" * 67 + "#")
    print("#" + " " * 24 + "RTL CONFIGURATION" + " " * 26 + "#")
    print("#" + "=" * 67 + "#")
    print()

    if rtl_config:
        max_name_len = max(len(name) for name in rtl_config.keys())
        for param_name, param_info in sorted(rtl_config.items()):
            default_value = param_info.get('default', 0)
            description = param_info.get('description', '')

            # Extract human-readable label for the current value from description
            # Descriptions contain patterns like "0=RV32I, 1=RV32E" or "0=none, 1=Zbb, ..."
            label = ''
            value_labels = re.findall(r'(\d+)=([^,(]+)', description)
            if value_labels:
                for val_str, val_label in value_labels:
                    if int(val_str) == default_value:
                        label = f'({val_label.strip()})'
                        break
            elif param_info.get('allowed', []) == [0, 1]:
                # Boolean parameter without value labels in description
                label = '(Enabled)' if default_value else '(Disabled)'

            # Format with label between value and comment
            label_str = f"  {label:<22s}" if label else " " * 24
            value_and_label = f"{default_value}{label_str}"
            print(f"         {param_name:<{max_name_len}s} = {value_and_label} # {description}")
    else:
        print("         No RTL configuration available")

    print()


def print_disabled_skipped_tests(disabled_tests: List[Dict], skipped_tests: List[Dict]):
    """
    Print list of disabled and skipped tests from configuration.

    Args:
        disabled_tests: List of test dictionaries that are disabled (enabled: false)
        skipped_tests: List of test dictionaries that don't meet requirements
    """
    print()
    print("#" + "=" * 67 + "#")
    print("#" + " " * 23 + "DISABLED & SKIPPED TESTS" + " " * 20 + "#")
    print("#" + "=" * 67 + "#")
    print()

    # Print disabled tests (exclude benchmarks)
    disabled_tests = [t for t in disabled_tests if not t.get('is_benchmark', False)]
    if disabled_tests:
        print(f"{Colors.CYAN} DISABLED TESTS (enabled: false):{Colors.NORMAL}")
        for test in disabled_tests:
            test_name = test['name']
            test_mode = test['mode']
            description = test.get('description', '')
            print(f"                 -  {test_name:<20s} ({test_mode:4s}) - {description}")
        print()

    # Print skipped tests
    if skipped_tests:
        print(f"{Colors.CYAN} SKIPPED TESTS (requirements not met):{Colors.NORMAL}")
        for test in skipped_tests:
            test_name = test['name']
            test_mode = test['mode']
            description = test.get('description', '')
            requires = test.get('requires', '')
            print(f"                 -  {test_name:<20s} ({test_mode:4s}) - {description}")
            print(f"                    {Colors.CYAN}requires: {requires}{Colors.NORMAL}")
        print()

    if not disabled_tests and not skipped_tests:
        print("         No disabled or skipped tests")
        print()


def print_benchmark_statistics(results: List[TestResult], metric_name: Optional[str] = None, current_score: Optional[float] = None):
    """
    Print the benchmark score for the current run.

    Cross-run statistics (min/max/avg/stdev/histogram, "N variants FAILED")
    used to be printed here but were dropped: parse_all_results aggregates
    every log in the dir regardless of mode/variant, so the historical
    sample mixed --mode std with --mode comp and different timing variants.
    Min/max/stdev across heterogeneous configs are not meaningful, and
    cross-config noise tracking belongs in a separate history tool.

    Args:
        results: List of TestResult objects (used as a fallback source for
            the score when current_score is not supplied -- e.g. when called
            from the single-iteration single-test path).
        metric_name: Optional metric name (e.g., 'CoreMark/MHz', 'DMIPS/MHz').
        current_score: Score of the run that just completed. Preferred over
            anything derived from `results`.
    """
    # Prefer the just-completed run's score. Otherwise fall back to the
    # most recently written scoring log -- that's almost certainly the run
    # that just finished when this function is called from a path that
    # doesn't thread current_score explicitly (runsim.py 2589/2612).
    score = current_score
    if score is None:
        scored = [r for r in results
                  if r.score is not None and r.status == 'PASSED']
        if scored:
            import os
            try:
                scored.sort(key=lambda r: os.path.getmtime(r.log_file))
                score = scored[-1].score
            except OSError:
                if len(scored) == 1:
                    score = scored[0].score
    if score is None:
        return

    if metric_name is None:
        metric_name = "Score"

    print()
    print("#" + "=" * 67 + "#")
    print("#" + " " * 24 + "BENCHMARK RESULTS" + " " * 26 + "#")
    print("#" + "=" * 67 + "#")
    print()
    print(f"{Colors.CYAN}{metric_name}:{Colors.NORMAL} {Colors.GREEN_BOLD}{score:,.2f}{Colors.NORMAL}")
    print()


def print_summary_report(results: List[TestResult]):
    """Print summary statistics."""
    counts = count_results(results)
    total = len(results)

    print()
    print("#" + "=" * 67 + "#")
    print("#" + " " * 28 + "SUMMARY REPORT" + " " * 25 + "#")
    print("#" + "=" * 67 + "#")
    print()
    print("         +-----------------------------------")
    print(f"         | Number of PASSED  tests :{Colors.GREEN_BOLD} {counts['PASSED']:3d} {Colors.NORMAL}")
    print(f"         | Number of FAILED  tests :{Colors.RED_BOLD} {counts['FAILED']:3d} {Colors.NORMAL}")
    print(f"         | Number of TIMEOUT tests :{Colors.YELLOW_BOLD} {counts['TIMEOUT']:3d} {Colors.NORMAL}")
    print(f"         | Number of ABORTED tests :{Colors.VIOLET_BOLD} {counts['ABORTED']:3d} {Colors.NORMAL}")
    print("         |----------------------------------")
    print(f"         | Number of tests         : {total:3d}")
    print("         +----------------------------------")
    print()
    print("         Make sure passed+skipped == total")
    print()
    print()


def parse_test_results_simple(test_name: str, mode_arg: str, log_dir: str) -> Tuple[int, int, int, int]:
    """
    Simple result parser for use by runsim.py during test execution.

    This function provides backward compatibility with the original parse_test_results
    function from runsim.py.

    Args:
        test_name: Name of the test
        mode_arg: Mode argument ('-c_mode' for compressed, '' for standard)
        log_dir: Directory containing log files

    Returns:
        Tuple of (passed_count, failed_count, timeout_count, aborted_count)
    """
    passed = 0
    failed = 0
    timeout = 0
    aborted = 0

    # Find all log files matching this test and mode
    # New naming: testname-std-*.log or testname-c-*.log
    mode_suffix = '-c' if mode_arg == '-c_mode' else '-std'
    pattern = f"{test_name}{mode_suffix}*.log"
    log_files = Path(log_dir).glob(pattern)

    for log_file in log_files:
        result = parse_log_file(str(log_file))
        if result.status == 'PASSED' or result.status == 'SKIPPED':
            passed += 1
        elif result.status == 'TIMEOUT':
            timeout += 1
        elif result.status == 'ABORTED':
            aborted += 1
        else:  # FAILED
            failed += 1

    return passed, failed, timeout, aborted


def main():
    """Main entry point for command-line usage."""
    # Parse arguments
    if len(sys.argv) > 2:
        print(f"Usage: {sys.argv[0]} [log_directory]", file=sys.stderr)
        print(f"       Default log_directory is ./log/0", file=sys.stderr)
        return 1

    log_dir = sys.argv[1] if len(sys.argv) == 2 else './log/0'

    # Check if log directory exists
    if not os.path.isdir(log_dir):
        print(f"Error: Log directory does not exist: {log_dir}", file=sys.stderr)
        return 1

    # Parse all results
    results = parse_all_results(log_dir)

    if not results:
        print(f"Warning: No log files found in {log_dir}", file=sys.stderr)
        return 0

    # Print reports
    print_detailed_report(results)
    print_summary_report(results)

    return 0


if __name__ == '__main__':
    sys.exit(main())
