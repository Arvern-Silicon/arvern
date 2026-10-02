#!/usr/bin/env python3
"""
work_session.py -- advisory session locks for the shared run/WORK directory.

Every simulation runs in its own run/WORK/tmpXXXX directory, and every
top-level runsim.py (or store_benchmark.py) invocation starts by sweeping
WORK/tmp* to reclaim leftovers from earlier sessions. The sweep cannot tell a
leftover from a directory that another, still-running session is using: a
single `runsim.py <test>` started while a `-regression` is in flight deletes
the regression's in-flight work directory from under it, and the regression
dies with FileNotFoundError.

This module makes that impossible:

  * acquire()        -- each session drops WORK/.session.<pid>.lock (removed
                        at exit; a lock whose pid is dead is stale and ignored)
  * sweep_tmp_dirs() -- refuses to delete anything while another live session
                        holds a lock, and says so; leftovers are reclaimed by
                        the next invocation that runs alone.

Both runsim.py and benchmark_trace_tools/store_benchmark.py use these instead
of their own rmtree loops.
"""

import atexit
import glob
import os
import shutil
import socket
import sys
import time

LOCK_PREFIX = '.session.'
LOCK_SUFFIX = '.lock'

_own_lock = None


def _lock_path(work_base, pid):
    return os.path.join(work_base, f'{LOCK_PREFIX}{pid}{LOCK_SUFFIX}')


def _pid_alive(pid):
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True      # exists, owned by someone else
    return True


def acquire(work_base):
    """Register this process as a live session of `work_base` (run/WORK).

    Idempotent. The lock is removed automatically at interpreter exit
    (normal exit, sys.exit, KeyboardInterrupt); a SIGKILL leaves a stale
    lock, which every later caller recognises by its dead pid and removes.
    """
    global _own_lock
    if _own_lock is not None:
        return _own_lock
    os.makedirs(work_base, exist_ok=True)
    path = _lock_path(work_base, os.getpid())
    with open(path, 'w') as f:
        f.write(f'pid={os.getpid()}\n'
                f'host={socket.gethostname()}\n'
                f'start={time.strftime("%Y-%m-%d %H:%M:%S")}\n'
                f'cmd={" ".join(sys.argv)}\n')
    _own_lock = path
    atexit.register(release)
    return path


def release():
    """Remove this process's lock (safe to call more than once)."""
    global _own_lock
    if _own_lock is None:
        return
    try:
        os.remove(_own_lock)
    except OSError:
        pass
    _own_lock = None


def live_sessions(work_base):
    """Return [(pid, cmd)] of OTHER sessions whose lock pid is still alive.

    Stale locks (dead pid) are removed on the way.
    """
    out = []
    for path in glob.glob(os.path.join(work_base, f'{LOCK_PREFIX}*{LOCK_SUFFIX}')):
        try:
            pid = int(os.path.basename(path)[len(LOCK_PREFIX):-len(LOCK_SUFFIX)])
        except ValueError:
            continue
        if pid == os.getpid():
            continue
        if not _pid_alive(pid):
            try:
                os.remove(path)
            except OSError:
                pass
            continue
        cmd = ''
        try:
            with open(path) as f:
                for line in f:
                    if line.startswith('cmd='):
                        cmd = line[4:].strip()
        except OSError:
            pass
        out.append((pid, cmd))
    return out


def sweep_tmp_dirs(work_base, verbose=True):
    """Delete WORK/tmp* leftovers -- unless another live session exists.

    Returns True if the sweep ran, False if it was skipped because another
    session is active (its in-flight tmp dirs are indistinguishable from
    leftovers, so nothing is touched).
    """
    if not os.path.isdir(work_base):
        return True
    others = live_sessions(work_base)
    if others:
        if verbose:
            print(f'NOTE: {len(others)} other runsim session(s) active in {work_base} -- '
                  f'skipping the WORK/tmp* sweep so their in-flight work dirs survive:')
            for pid, cmd in others:
                print(f'      pid {pid}: {cmd}')
        return False
    for d in glob.glob(os.path.join(work_base, 'tmp*')):
        if os.path.isdir(d):
            try:
                shutil.rmtree(d)
            except OSError:
                pass  # best effort
    return True
