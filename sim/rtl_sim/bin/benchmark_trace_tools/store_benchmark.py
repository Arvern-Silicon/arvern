#!/usr/bin/env python3
#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Script:    store_benchmark.py
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Persist a benchmark run summary to the snapshot store.
#----------------------------------------------------------------------------

"""
Run benchmarks and save execution traces with metadata.

This script runs a benchmark test, extracts the score from the log file,
and saves the execution trace (with embedded metadata) to the benchmark
traces directory.
"""

import io
import os
import sys
import argparse
import subprocess
import threading
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Tuple

# Add bin directory to path for imports (test_config, parse_results live in bin/)
_BIN = str(Path(__file__).resolve().parent.parent)
sys.path.insert(0, _BIN)
from test_config import TestConfig
from parse_results import parse_log_file
from .save_trace import save_trace as _save_trace


def extract_rtl_config(config_obj: TestConfig) -> Dict[str, int]:
    """
    Extract RTL configuration from test config.

    Args:
        config_obj: TestConfig instance

    Returns:
        Dictionary of RTL parameters
    """
    rtl_config = {}
    config_data = config_obj._config

    if "rtl_config" in config_data:
        for param, info in config_data["rtl_config"].items():
            rtl_config[param] = info.get("default", 0)

    return rtl_config


def parse_size_file(elf_file: Path, print_fn=print) -> Dict[str, int]:
    """
    Parse size information from ELF file using riscv64-unknown-elf-size.

    Uses size -A to get detailed section information including separate
    .text and .rodata sections.

    Args:
        elf_file: Path to the .elf file

    Returns:
        Dictionary with keys: text, rodata, data, bss (all in bytes)
        Returns zeros if file cannot be parsed
    """
    size_info = {"text": 0, "rodata": 0, "data": 0, "bss": 0}

    try:
        # Get size tool from march_config.sh (fallback to default)
        size_cmd = 'riscv64-unknown-elf-size'
        march_config = Path('march_config.sh')
        if march_config.exists():
            try:
                r = subprocess.run(['bash', '-c', 'source march_config.sh && echo $TC_SIZE'],
                                   capture_output=True, text=True)
                if r.returncode == 0 and r.stdout.strip():
                    size_cmd = r.stdout.strip()
            except Exception:
                pass

        # Run size -A to get section details
        result = subprocess.run(
            [size_cmd, '-A', str(elf_file)],
            capture_output=True,
            text=True,
            check=True
        )

        for line in result.stdout.splitlines():
            parts = line.split()
            if len(parts) >= 2:
                section = parts[0]
                try:
                    size = int(parts[1])
                    if section == '.text':
                        size_info['text'] = size
                    elif section == '.rodata':
                        size_info['rodata'] = size
                    elif section == '.data':
                        size_info['data'] = size
                    elif section == '.bss':
                        size_info['bss'] = size
                except (ValueError, IndexError):
                    continue

    except (FileNotFoundError, subprocess.CalledProcessError) as e:
        print_fn(f"Warning: Could not get size info from {elf_file}: {e}")

    return size_info


def list_available_benchmarks(config: TestConfig) -> None:
    """
    Display a list of available benchmark tests.

    Args:
        config: TestConfig instance
    """
    # Get all benchmark tests from config (regardless of enabled status)
    benchmarks = []
    for test in config._config.get("tests", []):
        if test.get("is_benchmark", False):
            benchmarks.append({
                "name": test["name"],
                "description": test.get("description", ""),
                "metric": test.get("score_metric", "")
            })

    if not benchmarks:
        print("No benchmarks found in configuration.")
        return

    print("\nAvailable Benchmarks:")
    print("=" * 80)

    # Group by category
    embench = [b for b in benchmarks if b["name"].startswith("embench_")]
    other = [b for b in benchmarks if not b["name"].startswith("embench_")]

    if other:
        print("\nCPU Benchmarks:")
        print("-" * 80)
        for b in other:
            print(f"  {b['name']:25s} - {b['description']}")
            if b['metric']:
                print(f"  {'':25s}   Metric: {b['metric']}")

    if embench:
        print(f"\nEmbench-IoT Benchmarks: ({len(embench)} benchmarks)")
        print("-" * 80)
        for b in embench:
            print(f"  {b['name']:25s} - {b['description']}")

    print(f"\nTotal: {len(benchmarks)} benchmarks available")
    print("\nUsage:")
    print("  ./run_benchmark <benchmark_name>")
    print("\nExamples:")
    if other:
        print(f"  ./run_benchmark {other[0]['name']}")
    if embench:
        print(f"  ./run_benchmark {embench[0]['name']}")
    print()


def run_benchmark(benchmark_name: str, run_args: Optional[List[str]] = None,
                  enable_dump: bool = False,
                  trace_dest: Optional[str] = None,
                  buffered: bool = False) -> Tuple[bool, str, str]:
    """
    Run a benchmark test and save its execution trace.

    Args:
        benchmark_name: Name of the benchmark test
        run_args: Additional arguments to pass to the run script
        enable_dump: Enable waveform dumping (default: False)
        trace_dest: Override destination path for asphalt.log (for parallel runs)
        buffered: Capture all output (prints + subprocess) into returned string
                  instead of printing to stdout directly. Used by parallel mode
                  so each benchmark's output is printed atomically on completion.

    Returns:
        (success, output) where output is the captured text (empty when buffered=False)
    """
    buf: Optional[io.StringIO] = io.StringIO() if buffered else None

    def _print(*args, **kwargs) -> None:
        if buf is not None:
            kwargs.pop('file', None)
            print(*args, file=buf, **kwargs)
        else:
            print(*args, **kwargs)
    # Get absolute paths
    script_dir = Path(__file__).resolve().parent
    run_dir = script_dir.parent.parent / "run"
    run_script = run_dir / "run"
    log_dir = run_dir / "log" / "0"

    # Load test configuration
    config_file = run_dir / "run_config.json"
    config = TestConfig(str(config_file))

    def _fail(msg: str) -> Tuple[bool, str, str]:
        _print(msg)
        return (False, buf.getvalue() if buf is not None else "", "")

    # Verify this is a benchmark test
    if not config.is_benchmark(benchmark_name):
        _print(f"\nError: '{benchmark_name}' is not configured as a benchmark test")
        list_available_benchmarks(config)
        return _fail("")

    # Get benchmark info
    benchmark_pattern = config.get_benchmark_pattern(benchmark_name)
    benchmark_metric = config.get_benchmark_metric(benchmark_name)

    # Build run command
    cmd = [str(run_script), benchmark_name]
    if not enable_dump:
        cmd.append('-nodump')   # prevents ./run from overriding SIMULATION_NODUMP=0
    if run_args:
        cmd.extend(run_args)

    # Format the time as [YYYY/MM/DD][HH:MM]
    now = datetime.now()
    formatted_date = now.strftime("[%Y/%m/%d][%H:%M]")

    _print("=" * 120)
    _print("=" * 120)
    _print(f"{formatted_date} Running benchmark: {benchmark_name}")
    _print(f"{formatted_date} Command: {Path(' '.join(cmd)).resolve()}")
    _print("=" * 120)
    _print("=" * 120)

    # Run the benchmark
    try:
        # Set up environment: disable waveform dump, keep trace enabled
        run_env = os.environ.copy()
        run_env['SIMULATION_NODUMP'] = '0' if enable_dump else '1'
        run_env['SIMULATION_NOTRACE'] = '0'  # Always enable trace for benchmarks
        if trace_dest:
            run_env['SIMULATION_TRACE_DEST'] = trace_dest
        # store_benchmark.main() already swept WORK/tmp* before spawning workers.
        # Tell each runsim.py subprocess to skip its own sweep so concurrent -j N
        # workers don't delete each other's in-flight tmp dirs.
        run_env['RUNSIM_SKIP_SWEEP'] = '1'

        result = subprocess.run(
            cmd,
            cwd=str(run_dir),
            capture_output=buffered,  # buffer in parallel mode, stream in sequential
            text=True,
            env=run_env
        )

        if buffered and buf is not None:
            if result.stdout:
                buf.write(result.stdout)
            if result.stderr:
                buf.write(result.stderr)

        if result.returncode != 0:
            return _fail(f"\nError: Benchmark execution failed with return code {result.returncode}")
    except subprocess.CalledProcessError as e:
        return _fail(f"\nError running benchmark: {e}")

    # Find the log file
    log_files = list(log_dir.glob(f"{benchmark_name}*.log"))
    if not log_files:
        return _fail(f"\nError: No log file found for {benchmark_name}")

    # Use the most recent log file
    log_file = max(log_files, key=lambda p: p.stat().st_mtime)

    # Parse the log file to extract the score
    test_result = parse_log_file(str(log_file), benchmark_pattern)

    if test_result.status != 'PASSED':
        return _fail(f"\nError: Benchmark did not pass (status: {test_result.status})")

    if test_result.score is None:
        return _fail(f"\nError: Could not extract score from log file")

    _print("-" * 80)
    _print(f"Benchmark completed successfully!")
    _print(f"Score: {test_result.score} {benchmark_metric}")

    # Find and parse the ELF file for size information
    src_c_dir = script_dir.parent.parent / "src-c"
    elf_file = src_c_dir / benchmark_name / f"{benchmark_name}.elf"

    size_info = parse_size_file(elf_file, print_fn=_print)
    _print(f"Binary size: text={size_info['text']}, rodata={size_info['rodata']}, " +
           f"data={size_info['data']}, bss={size_info['bss']}")

    # Determine mode (std or comp) - default to std
    mode = "comp" if run_args and "-c_mode" in run_args else "std"

    # Extract variant flags from run_args for trace metadata (exclude mode flags like -c_mode)
    _VARIANT_FLAGS = frozenset([
        '-rwsrom', '-wsrom', '-rwsram', '-wssram', '-rwsper', '-wsper',
        '-rsalu', '-salu', '-gahb', '-fahb', '-rirq',
    ])
    trace_variant_args = [a for a in (run_args or []) if a in _VARIANT_FLAGS]

    # Save trace (asphalt.log is always written by the simulator)
    trace_source = Path(trace_dest) if trace_dest else run_dir / "asphalt.log"
    if trace_source.exists():
        traces_dir = run_dir / "benchmark_traces" / "latest"
        _save_trace(
            test=benchmark_name,
            mode=mode,
            variant_args=trace_variant_args,
            compress=True,
            outdir=str(traces_dir),
            source=str(trace_source),
            score=test_result.score,
            score_metric=benchmark_metric,
            size_info=size_info,
            quiet=buffered,
        )

    score_str = f"{test_result.score:.2f} {benchmark_metric}"
    _print(f"\nResult: {score_str}")

    return (True, buf.getvalue() if buf is not None else "", score_str)


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description='Run benchmarks and save execution traces',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Run benchmarks (waveform dumping disabled by default)
  %(prog)s embench_statemate
  %(prog)s coremark -c_mode
  %(prog)s embench_st -all
  %(prog)s embench_statemate --dump             # Enable waveform dumping
  %(prog)s -a                                    # Run ALL benchmarks

Run without arguments to see list of available benchmarks:
  %(prog)s
        """
    )

    parser.add_argument('benchmark', nargs='?', help='Benchmark test name (e.g., embench_statemate)')
    parser.add_argument('-a', '--all', action='store_true',
                       help='Run all benchmarks from run_config.json')
    parser.add_argument('-j', type=int, default=1, metavar='N',
                       help='Number of parallel benchmark workers (only valid with -a)')
    parser.add_argument('-m', '--mode', choices=['auto', 'std', 'comp'], default='auto',
                       help='Test mode: auto (default; picks comp when run_config.json has C_EXTENSION>=1, std otherwise), std, or comp (explicit)')
    parser.add_argument('--rtl-config', metavar='N_OR_NAME',
                       help='Build + benchmark a specific RTL configuration. Accepts either a 1-based integer index into the sweep set or a persona name (minimal / medium / full). Forwarded to `./run` as `-rtl_config <value>`.')
    parser.add_argument('--dump', action='store_true',
                       help='Enable waveform dumping (disabled by default for faster simulation)')
    parser.add_argument('extra_args', nargs='*', help='Additional arguments to pass to run script')

    args = parser.parse_args()

    script_dir = Path(__file__).resolve().parent

    # Resolve --mode auto by peeking at C_EXTENSION in run_config.json. Comp
    # builds require Zca (C_EXTENSION>=1); on a C-less build the comp
    # toolchain target doesn't exist and the run would fail. Auto-pick:
    #   C_EXTENSION>=1  -> 'comp' (use the RV32IMC binary the build targets)
    #   C_EXTENSION==0  -> 'std'  (use the RV32IM-only binary)
    # An explicit '-m std' / '-m comp' bypasses this resolution.
    if args.mode == 'auto':
        try:
            _config = TestConfig(str(script_dir.parent.parent / "run" / "run_config.json"))
            _c_ext = int(_config.get_rtl_config().get('C_EXTENSION', {}).get('default', 0))
            args.mode = 'comp' if _c_ext >= 1 else 'std'
            print(f"[run_benchmark] --mode auto -> '{args.mode}' (C_EXTENSION={_c_ext} in run_config.json)")
        except Exception as e:
            print(f"[run_benchmark] --mode auto: could not read C_EXTENSION ({e}); falling back to 'std'")
            args.mode = 'std'

    # Sweep WORK/tmp* leftovers up front, BEFORE any ./run worker is spawned.
    # With -j N each worker is a separate runsim.py subprocess; if each one
    # swept on its own, siblings would delete each other's in-flight tmp dirs.
    # We sweep here once, then pass RUNSIM_SKIP_SWEEP=1 to each subprocess
    # (set in run_benchmark()'s run_env) so workers skip their own sweep.
    _run_dir = script_dir.parent.parent / "run"
    _work_base = _run_dir / "WORK"
    if _work_base.is_dir():
        import shutil as _shutil
        for _d in _work_base.glob("tmp*"):
            if _d.is_dir():
                try:
                    _shutil.rmtree(_d)
                except OSError:
                    pass

    # In --all mode treat the batch like a regression: only keep failed-test
    # work dirs. Without this, every passing benchmark's tmp dir would survive
    # until the next sweep, piling up GBs during a single run_benchmark -a.
    # Inherited by run_env via os.environ.copy() in run_benchmark().
    if args.all:
        os.environ['RUNSIM_NO_KEEP'] = '1'

    # Run all benchmarks mode
    if args.all:
        # Load test config to get all benchmarks
        run_dir = script_dir.parent.parent / "run"
        config_file = run_dir / "run_config.json"
        config = TestConfig(str(config_file))

        # Get all benchmark tests
        all_benchmarks = []
        for test in config._config.get("tests", []):
            if test.get("is_benchmark", False):
                all_benchmarks.append(test["name"])

        if not all_benchmarks:
            print("\nNo benchmarks found in run_config.json")
            sys.exit(1)

        workers = max(1, args.j)
        print(f"\n{'='*120}")
        print(f"Running ALL benchmarks ({len(all_benchmarks)} total, j={workers})")
        print(f"{'='*120}\n")

        # Track results
        successful = []
        failed = []

        # Build run arguments.
        # argparse parks the first positional after '--' in args.benchmark (nargs='?')
        # rather than args.extra_args — absorb it here so '--all -- -fahb' works.
        extra = ([args.benchmark] if args.benchmark else []) + list(args.extra_args or [])
        run_args = extra
        if args.mode == 'comp':
            run_args.append('-c_mode')
        if args.rtl_config:
            run_args.extend(['-rtl_config', args.rtl_config])

        sorted_benchmarks = sorted(all_benchmarks)
        batch_start_time = time.time()

        if workers == 1:
            # Sequential path — output streams to terminal in real-time
            for idx, benchmark_name in enumerate(sorted_benchmarks, 1):
                print(f"\n[{idx}/{len(sorted_benchmarks)}] Starting {benchmark_name}...")
                print("-" * 120)
                success, _, score_str = run_benchmark(
                    benchmark_name=benchmark_name,
                    run_args=run_args,
                    enable_dump=args.dump,
                    buffered=False,
                )
                if success:
                    successful.append(benchmark_name)
                    print(f"✓ {benchmark_name} — {score_str}")
                else:
                    failed.append(benchmark_name)
                    print(f"✗ {benchmark_name} failed")
                print("-" * 120)
        else:
            # Parallel path — output is buffered per-benchmark and flushed atomically
            # on completion so runs don't interleave.  The terminal is split into two
            # zones: a permanent "done" zone (lines printed once and never touched
            # again) and a dynamic "ongoing" zone below it that is redrawn every
            # second by the ticker thread using ANSI cursor movement.  When a
            # benchmark completes its line moves from the ongoing zone into the done
            # zone, so done results accumulate at the top and in-progress work stays
            # at the bottom.
            total = len(sorted_benchmarks)
            w  = len(str(total))                          # digit width for counters
            nw = max(len(n) for n in sorted_benchmarks)   # name width for score alignment
            started_count = 0
            done_count = 0
            # name -> (start_time, started_index), guarded by print_lock
            ongoing:     Dict[str, Tuple[float, int]] = {}
            start_times: Dict[str, float] = {}  # survives removal from ongoing
            _dyn = [0]  # _dyn[0] = number of lines currently in the dynamic area
            print_lock = threading.Lock()

            def _fmt(label: str, n: int) -> str:
                return f"[{label:<7} {n:{w}}/{total}]"

            def _cols() -> int:
                try:
                    return os.get_terminal_size().columns
                except OSError:
                    return 120

            def _hms(ts: float) -> str:
                """Format seconds elapsed since batch start as HH:MM:SS."""
                secs = int(ts - batch_start_time)
                h, rem = divmod(secs, 3600)
                m, s   = divmod(rem, 60)
                return f"{h:02d}:{m:02d}:{s:02d}"

            def _mmss(secs: int) -> str:
                """Format a duration in seconds as MM:SS."""
                return f"{secs // 60:02d}:{secs % 60:02d}"

            def _clear_dynamic() -> None:
                """Move cursor up to the start of the dynamic area and erase it."""
                if _dyn[0] > 0:
                    print(f"\033[{_dyn[0]}A", end='')   # cursor up N lines
                    print("\033[J", end='', flush=True)  # erase from cursor to end
                    _dyn[0] = 0

            def _redraw_dynamic() -> None:
                """Reprint the ongoing-benchmark lines. Must be called under print_lock."""
                now = time.time()
                cols = _cols()
                count = 0
                if ongoing:
                    print("─" * min(cols - 1, 120))
                    count += 1
                for bname, (start_time, idx) in ongoing.items():
                    elapsed = int(now - start_time)
                    line = (f"[{_hms(start_time)}] {_fmt('ongoing', idx)}"
                            f" → {bname:<{nw}}  ({_mmss(elapsed)})")
                    if len(line) > cols:
                        line = line[:cols]
                    print(line)
                    count += 1
                _dyn[0] = count
                sys.stdout.flush()

            status_stop = threading.Event()

            def _ticker() -> None:
                while not status_stop.wait(1.0):
                    with print_lock:
                        if ongoing:
                            _clear_dynamic()
                            _redraw_dynamic()

            ticker_thread = threading.Thread(target=_ticker, daemon=True)
            ticker_thread.start()

            def _run_one(benchmark_name: str) -> Tuple[bool, str, str]:
                nonlocal started_count
                trace_dest = str(run_dir / f"asphalt_{benchmark_name}.log")
                start_time = time.time()
                with print_lock:
                    started_count += 1
                    sc = started_count
                    _clear_dynamic()
                    start_times[benchmark_name] = start_time
                    ongoing[benchmark_name] = (start_time, sc)
                    _redraw_dynamic()
                try:
                    return run_benchmark(
                        benchmark_name=benchmark_name,
                        run_args=run_args,
                        enable_dump=args.dump,
                        trace_dest=trace_dest,
                        buffered=True,
                    )
                finally:
                    with print_lock:
                        ongoing.pop(benchmark_name, None)

            print(f"[parallel] Submitting {total} benchmarks to {workers} workers...\n")
            interrupted = False
            future_to_name: Dict = {}
            try:
                with ThreadPoolExecutor(max_workers=workers) as executor:
                    future_to_name = {executor.submit(_run_one, name): name for name in sorted_benchmarks}
                    for future in as_completed(future_to_name):
                        name = future_to_name[future]
                        try:
                            success, _, score_str = future.result()
                        except Exception as exc:
                            with print_lock:
                                done_count += 1
                                _clear_dynamic()
                                now = time.time()
                                st  = start_times.get(name, now)
                                print(f"[{_hms(now)}] {_fmt('done', done_count)}"
                                      f" → {name:<{nw}}  ({_mmss(int(now - st))})"
                                      f"  exception: {exc}", flush=True)
                                _redraw_dynamic()
                            failed.append(name)
                            continue
                        with print_lock:
                            done_count += 1
                            _clear_dynamic()
                            now = time.time()
                            st  = start_times.get(name, now)
                            duration_str = _mmss(int(now - st))
                            result_str = f"  — {score_str}" if success and score_str else "  FAILED"
                            print(f"[{_hms(now)}] {_fmt('done', done_count)}"
                                  f" → {name:<{nw}}  ({duration_str}){result_str}", flush=True)
                            _redraw_dynamic()
                        if success:
                            successful.append(name)
                        else:
                            failed.append(name)
            except KeyboardInterrupt:
                interrupted = True
                # Cancel futures that haven't started yet; running threads will
                # finish shortly because their ./run subprocess also received SIGINT.
                for f in future_to_name:
                    f.cancel()
            finally:
                status_stop.set()
                ticker_thread.join(timeout=2)
                with print_lock:
                    _clear_dynamic()

            if interrupted:
                total_secs = int(time.time() - batch_start_time)
                h, rem = divmod(total_secs, 3600)
                m, s   = divmod(rem, 60)
                total_str = f"{h:02d}:{m:02d}:{s:02d}" if h else f"{m:02d}:{s:02d}"
                print(f"\n[interrupted] Run aborted after {total_str}."
                      f"  {done_count}/{total} benchmarks completed.")
                sys.exit(130)

        # Print summary
        total_secs = int(time.time() - batch_start_time)
        h, rem = divmod(total_secs, 3600)
        m, s   = divmod(rem, 60)
        total_str = f"{h:02d}:{m:02d}:{s:02d}" if h else f"{m:02d}:{s:02d}"
        print(f"\n{'='*120}")
        print(f"BATCH RUN COMPLETE  ({total_str})")
        print(f"{'='*120}")
        print(f"\nTotal:      {len(all_benchmarks)}")
        print(f"Successful: {len(successful)}")
        print(f"Failed:     {len(failed)}")

        if successful:
            print(f"\n✓ Successful ({len(successful)}):")
            for bench in successful:
                print(f"  - {bench}")

        if failed:
            print(f"\n✗ Failed ({len(failed)}):")
            for bench in failed:
                print(f"  - {bench}")

        print(f"\n{'='*120}\n")

        # Exit with error code if any failed
        sys.exit(0 if not failed else 1)

    # If no benchmark specified, show list and exit
    if not args.benchmark:
        run_dir = script_dir.parent.parent / "run"
        config_file = run_dir / "run_config.json"
        config = TestConfig(str(config_file))
        list_available_benchmarks(config)
        sys.exit(0)

    # Build run arguments
    run_args = list(args.extra_args) if args.extra_args else []
    if args.mode == 'comp':
        run_args.append('-c_mode')
    if args.rtl_config:
        run_args.extend(['-rtl_config', args.rtl_config])
    # Run benchmark and save trace (single run — stream output to terminal)
    success, _, _ = run_benchmark(
        benchmark_name=args.benchmark,
        run_args=run_args,
        enable_dump=args.dump
    )

    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
