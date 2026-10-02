"""Repository-specific settings of cov_const.py (arvern core).

TOP                 top module elaborated by Yosys
rtl_files()         RTL sources, absolute paths
coverage_configs()  [(label, {PARAM: value})] -- every configuration the coverage
                    sweep builds; a bit is waived only if constant in all of them
"""
import os

_BIN = os.path.dirname(os.path.abspath(__file__))
RTL_DIR = os.path.normpath(os.path.join(_BIN, '..', '..', '..', 'rtl', 'verilog'))
RUN_CONFIG = os.path.normpath(os.path.join(_BIN, '..', 'run', 'run_config.json'))

TOP = 'arvern'


def rtl_files():
    return [os.path.join(RTL_DIR, l.strip()) for l in open(os.path.join(RTL_DIR, 'filelist.f'))
            if l.strip() and not l.strip().startswith(('//', '+', '-'))]


def coverage_configs():
    import rtl_sweep_configs as rsc
    params = rsc.load_rtl_config(RUN_CONFIG)
    return [(label, rsc.resolve_persona(label, params)[1]) for label, _ in rsc.COVERAGE_CONFIGS]
