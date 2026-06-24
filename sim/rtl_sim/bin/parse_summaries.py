#!/usr/bin/env python3
#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Script:    parse_summaries.py
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Roll up multiple regression summaries (e.g., across iterations) into one report.
#----------------------------------------------------------------------------

"""
Parse and aggregate results from multiple regression summary files.

This module analyzes summary.*.log files from multiple regression iterations
and provides comprehensive reporting on test results across all runs.
"""

import os
import sys
import re
from pathlib import Path
from typing import Dict, List, Tuple
from dataclasses import dataclass, field
from collections import defaultdict


# ANSI color codes
class Colors:
    YELLOW       = '\033[33m'
    GREEN        = '\033[32m'
    GREEN_BOLD   = '\033[1m\033[32m'
    RED          = '\033[31m'
    RED_BOLD     = '\033[1m\033[31m'
    VIOLET       = '\033[35m'
    VIOLET_BOLD  = '\033[1m\033[35m'
    NORMAL       = '\033[0m'


@dataclass
class TestStats:
    """Statistics for a test across multiple regression iterations."""
    testname: str
    passed: int = 0
    skipped: int = 0
    failed: int = 0
    aborted: int = 0
    failing_indexes: List[int] = field(default_factory=list)

    @property
    def total(self) -> int:
        return self.passed + self.skipped + self.failed + self.aborted

    @property
    def has_failures(self) -> bool:
        return self.failed > 0 or self.aborted > 0


def extract_regression_index(filename: str) -> int:
    """
    Extract regression iteration index from summary filename.

    Args:
        filename: Summary file name like "summary.0.log" or "summary.5.log"

    Returns:
        Iteration index as integer
    """
    match = re.search(r'summary\.(\d+)\.log', filename)
    if match:
        return int(match.group(1))
    return 0


def parse_summary_file(filepath: str) -> Tuple[int, List[Tuple[str, str]]]:
    """
    Parse a single summary file to extract test results.

    Args:
        filepath: Path to summary.*.log file

    Returns:
        Tuple of (regression_index, list of (testname, status) tuples)
    """
    regression_index = extract_regression_index(os.path.basename(filepath))
    results = []

    try:
        with open(filepath, 'r') as f:
            for line in f:
                # Look for lines containing "runsim" (these are test result lines)
                if 'runsim' in line:
                    # Extract test name and status from the line
                    # Format: "# testname || STATUS ||"
                    match = re.search(r'#\s+(\S+)\s+\|\|.*\|\|\s+(\w+)\s+\|\|', line)
                    if match:
                        testname = match.group(1)
                        status = match.group(2)
                        results.append((testname, status))
                    else:
                        # Alternative format check - look for runsim command with status
                        if 'PASSED' in line:
                            status = 'PASSED'
                        elif 'SKIPPED' in line:
                            status = 'SKIPPED'
                        elif 'FAILED' in line:
                            status = 'FAILED'
                        elif 'ABORTED' in line:
                            status = 'ABORTED'
                        else:
                            continue

                        # Extract testname from runsim command
                        parts = line.split()
                        for i, part in enumerate(parts):
                            if 'runsim' in part and i + 1 < len(parts):
                                testname = parts[i + 1]
                                results.append((testname, status))
                                break
    except Exception as e:
        print(f"Warning: Error parsing {filepath}: {e}", file=sys.stderr)

    return regression_index, results


def aggregate_results(summary_files: List[str]) -> Tuple[Dict[str, TestStats], Dict[str, int]]:
    """
    Aggregate results from multiple summary files.

    Args:
        summary_files: List of paths to summary.*.log files

    Returns:
        Tuple of (test_stats_dict, overall_counts_dict)
    """
    test_stats = defaultdict(lambda: TestStats(testname=""))
    overall_counts = {
        'passed': 0,
        'skipped': 0,
        'failed': 0,
        'aborted': 0
    }

    total_files = len(summary_files)

    for idx, filepath in enumerate(summary_files, 1):
        # Progress indicator
        progress = (idx / total_files) * 100
        print(f"\rProcessing summary files... {progress:6.2f}%", end='', flush=True)

        regression_index, results = parse_summary_file(filepath)

        for testname, status in results:
            if testname not in test_stats:
                test_stats[testname] = TestStats(testname=testname)

            stats = test_stats[testname]

            if status == 'PASSED':
                stats.passed += 1
                overall_counts['passed'] += 1
            elif status == 'SKIPPED':
                stats.skipped += 1
                overall_counts['skipped'] += 1
            elif status == 'FAILED':
                stats.failed += 1
                overall_counts['failed'] += 1
                if regression_index not in stats.failing_indexes:
                    stats.failing_indexes.append(regression_index)
            elif status == 'ABORTED':
                stats.aborted += 1
                overall_counts['aborted'] += 1
                if regression_index not in stats.failing_indexes:
                    stats.failing_indexes.append(regression_index)

    print()  # Newline after progress

    return dict(test_stats), overall_counts


def print_detailed_report(test_stats: Dict[str, TestStats], show_all: bool = True):
    """Print detailed test statistics table.

    Args:
        test_stats: Dictionary of test statistics
        show_all: If True, show all tests. If False, only show tests with failures (default: True for aggregate view)
    """
    # Filter test stats if show_all is False
    if not show_all:
        filtered_stats = {name: stats for name, stats in test_stats.items() if stats.has_failures}
        if not filtered_stats:
            # No failures to show
            print()
            print("#" + "=" * 67 + "#")
            print("#" + " " * 20 + "DETAILED REPORT" + " " * 32 + "#")
            print("#" + "=" * 67 + "#")
            print()
            print(f"         {Colors.GREEN}All tests passed in all iterations!{Colors.NORMAL}")
            print(f"         Use --report-show-all to see all test results")
            print()
            return
    else:
        filtered_stats = test_stats

    print()
    print("#" + "=" * 171 + "#")
    print("#" + " " * 171 + "#")
    header_text = "DETAILED REPORT" if show_all else "DETAILED REPORT (FAILURES ONLY)"
    padding = (171 - len(header_text)) // 2
    print("#" + " " * padding + header_text + " " * (171 - padding - len(header_text)) + "#")
    print("#" + " " * 171 + "#")
    print("#" + "=" * 171 + "#")
    print("#" + " " * 39 + "||" + " " * 27 + "RESULTS" + " " * 22 + "||" + " " * 73 + "#")
    print("#" + " " * 15 + "TEST NAME" + " " * 15 + "||" + "-" * 55 + "||" + " " * 23 + "FAILING REGRESSION INDEXES" + " " * 24 + "#")
    print("#" + " " * 39 + "||  Passed  |  Skipped  |  Failed  |  Aborted  |  Total  ||" + " " * 73 + "#")
    print("#" + "=" * 39 + "++" + "=" * 10 + "+" + "=" * 11 + "+" + "=" * 10 + "+" + "=" * 11 + "+" + "=" * 9 + "++" + "=" * 73 + "#")
    print("#" + " " * 39 + "||" + " " * 10 + "|" + " " * 11 + "|" + " " * 10 + "|" + " " * 11 + "|" + " " * 9 + "||" + " " * 73 + "#")

    # Sort test names for consistent output
    for testname in sorted(filtered_stats.keys()):
        stats = filtered_stats[testname]

        # Format failing indexes
        if stats.failing_indexes:
            failing_str = " ".join(str(i) for i in sorted(stats.failing_indexes))
        else:
            failing_str = "-"

        # Add color based on status
        if stats.has_failures:
            testname_color = f"{Colors.RED} {testname} {Colors.NORMAL}"
            passed_color = f"{Colors.NORMAL} {stats.passed} {Colors.NORMAL}"

            if stats.failed > 0:
                failed_color = f"{Colors.RED} {stats.failed} {Colors.NORMAL}"
            else:
                failed_color = f"{Colors.NORMAL} {stats.failed} {Colors.NORMAL}"

            if stats.aborted > 0:
                aborted_color = f"{Colors.VIOLET} {stats.aborted} {Colors.NORMAL}"
            else:
                aborted_color = f"{Colors.NORMAL} {stats.aborted} {Colors.NORMAL}"

            # Print with proper formatting
            print(f"#  {testname_color:47s} || {passed_color:20s} | {stats.skipped:8d}  | {failed_color:19s} | {aborted_color:20s} | {stats.total:6d}  ||  {failing_str:70s} #")
        else:
            testname_color = f"{Colors.NORMAL} {testname} {Colors.NORMAL}"

            if stats.passed > 0:
                passed_color = f"{Colors.GREEN} {stats.passed} {Colors.NORMAL}"
            else:
                passed_color = f"{Colors.YELLOW} {stats.passed} {Colors.NORMAL}"

            failed_color = f"{Colors.NORMAL} {stats.failed} {Colors.NORMAL}"
            aborted_color = f"{Colors.NORMAL} {stats.aborted} {Colors.NORMAL}"

            print(f"#  {testname_color:48s} || {passed_color:19s} | {stats.skipped:8d}  | {failed_color:20s} | {aborted_color:21s} | {stats.total:6d}  ||  {failing_str:70s} #")

    print("#" + " " * 39 + "||" + " " * 10 + "|" + " " * 11 + "|" + " " * 10 + "|" + " " * 11 + "|" + " " * 9 + "||" + " " * 73 + "#")
    print("#" + "=" * 171 + "#")
    print()


def print_failing_regressions(log_dir: str):
    """Print details of failing regressions."""
    print()
    print("#" + "=" * 151 + "#")
    print("#" + " " * 65 + "FAILING REGRESSIONS" + " " * 67 + "#")
    print("#" + "=" * 151 + "#")
    print()

    # Find all summary files and extract FAILED lines
    summary_files = sorted(Path(log_dir).glob('summary.*.log'))

    failed_lines = []
    for filepath in summary_files:
        try:
            with open(filepath, 'r') as f:
                for line in f:
                    if 'FAILED' in line and 'SKIPPED' not in line and 'TESTS' not in line and 'Number' not in line:
                        # Extract the relevant part of the line (replay command and log file)
                        parts = line.split('||')
                        if len(parts) >= 3:
                            # Get everything after the second ||
                            cleaned = '||'.join(parts[2:])
                            cleaned = cleaned.strip().rstrip('#').strip()
                            cleaned = cleaned.replace('||', '--->')
                            failed_lines.append(cleaned)
        except Exception:
            pass

    if failed_lines:
        for line in failed_lines:
            print(f"         {line}")
    else:
        print("         (none)")

    print()


def print_summary_report(overall_counts: Dict[str, int], log_dir: str):
    """Print overall summary statistics."""
    print()
    print("#" + "=" * 151 + "#")
    print("#" + " " * 67 + "SUMMARY REPORT" + " " * 70 + "#")
    print("#" + "=" * 151 + "#")
    print()

    print( "         +-----------------------------------")
    print(f"         | Number of PASSED  tests :{Colors.GREEN_BOLD} {overall_counts['passed']:6d} {Colors.NORMAL}")
    print(f"         | Number of FAILED  tests :{Colors.RED_BOLD} {overall_counts['failed']:6d} {Colors.NORMAL}")
    print(f"         | Number of ABORTED tests :{Colors.VIOLET_BOLD} {overall_counts['aborted']:6d} {Colors.NORMAL}")
    print( "         |----------------------------------")

    # Count total log files across all iterations
    total_logs = len(list(Path(log_dir).glob('*/*.log')))
    print(f"         | Number of tests         : {total_logs:6d}")

    print( "         +----------------------------------")
    print()
    print("         Make sure passed+skipped == total")
    print()
    print()


def main():
    """Main entry point for command-line usage."""
    # Parse arguments
    if len(sys.argv) > 2:
        print(f"Usage: {sys.argv[0]} [summary_files_pattern]", file=sys.stderr)
        print(f"       Default is ./log/summary.*.log", file=sys.stderr)
        return 1

    if len(sys.argv) == 2:
        # User provided pattern
        pattern = sys.argv[1]
        if '*' in pattern:
            # It's a glob pattern
            from glob import glob
            summary_files = sorted(glob(pattern))
        else:
            # It's a single file
            summary_files = [pattern] if os.path.exists(pattern) else []
    else:
        # Default: find all summary.*.log files in ./log/
        log_dir = './log'
        summary_files = sorted(Path(log_dir).glob('summary.*.log'))
        summary_files = [str(f) for f in summary_files]

    if not summary_files:
        print("Warning: No summary files found", file=sys.stderr)
        return 0

    print(f"\nFound {len(summary_files)} summary file(s)")

    # Aggregate results from all summary files
    test_stats, overall_counts = aggregate_results(summary_files)

    # Print reports
    print_detailed_report(test_stats)

    # Determine log directory for failing regressions
    if summary_files:
        log_dir = os.path.dirname(summary_files[0]) if os.path.dirname(summary_files[0]) else './log'
    else:
        log_dir = './log'

    print_failing_regressions(log_dir)
    print_summary_report(overall_counts, log_dir)

    return 0


if __name__ == '__main__':
    sys.exit(main())
