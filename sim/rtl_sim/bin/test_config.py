#!/usr/bin/env python3
#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Script:    test_config.py
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Read and query the test configuration in run/run_config.json.
#----------------------------------------------------------------------------

"""
Test configuration management for arvern RTL simulation.

This module provides functions to read and query the test configuration
from run_config.json.
"""

import json
import os
from typing import List, Dict, Optional, Iterator, Tuple

from rtl_sweep_configs import generate_configs, sweepable_params


class TestConfig:
    """Manages test configuration from JSON file."""

    def __init__(self, config_path: Optional[str] = None):
        """
        Initialize test configuration.

        Args:
            config_path: Path to run_config.json. If None, looks in current directory.
        """
        if config_path is None:
            config_path = os.path.join(os.getcwd(), 'run_config.json')

        self.config_path = config_path
        # Always a dict after __init__: _load_config() populates it and
        # raises on any failure, so it is never None when accessed later.
        self._config: Dict = {}
        self._load_config()

    def _load_config(self):
        """Load configuration from JSON file."""
        try:
            with open(self.config_path, 'r') as f:
                self._config = json.load(f)
        except FileNotFoundError:
            raise FileNotFoundError(f"Configuration file not found: {self.config_path}")
        except json.JSONDecodeError as e:
            raise ValueError(f"Invalid JSON in configuration file: {e}")

        # Validate configuration after loading
        self._validate_config()

    def _validate_config(self):
        """Validate RTL configuration parameters."""
        rtl_config = self._config.get('rtl_config', {})
        errors = []

        for param_name, param_info in rtl_config.items():
            default_value = param_info.get('default')
            raw_allowed   = param_info.get('allowed', None)

            # An explicit empty 'allowed' list ([]) marks a *free-valued*
            # parameter (e.g. a 32-bit MVENDORID): it has no finite
            # enumeration, is fixed at 'default', and is never swept (the
            # shared sweep generator skips it). The default-membership
            # check below does not apply. (The former per-parameter "enable"
            # subkey is obsolete -- sweepability is derived, not flagged.)
            if raw_allowed == []:
                continue

            # 'allowed' is a required field; a missing key is a config mistake
            # (use an explicit [] only to mark a free-valued, non-swept param).
            if raw_allowed is None:
                errors.append(
                    f"Parameter '{param_name}': required field 'allowed' is missing"
                )
                continue

            # Check if default is in allowed list
            if default_value is not None and default_value not in raw_allowed:
                errors.append(
                    f"Parameter '{param_name}': default value {default_value} is not in allowed list {raw_allowed}"
                )

        if errors:
            error_msg = "Configuration validation failed:\n" + "\n".join(f"  - {err}" for err in errors)
            raise ValueError(error_msg)

    def get_test_mode(self, test_name: str) -> str:
        """
        Get the instruction mode for a test.

        Args:
            test_name: Name of the test

        Returns:
            Test mode (STD, COMP, or BOTH), defaults to STD if not found
        """
        for test in self._config.get('tests', []):
            if test['name'] == test_name:
                return test.get('mode', 'STD')
        return 'STD'

    def is_test_enabled(self, test_name: str) -> bool:
        """
        Check if a test is enabled.

        Args:
            test_name: Name of the test

        Returns:
            True if enabled, False otherwise
        """
        for test in self._config.get('tests', []):
            if test['name'] == test_name:
                return test.get('enabled', True)
        return True

    def get_all_tests(self) -> List[Dict]:
        """
        Get all tests from configuration.

        Returns:
            List of test dictionaries
        """
        return self._config.get('tests', [])

    def _get_full_requires_expr(self, test: Dict) -> str:
        """
        Get the full requirements expression for a test, including implicit requirements.
        Automatically adds C_EXTENSION>=1 for COMP mode tests.

        Args:
            test: Test dictionary

        Returns:
            Full requirements expression string, or empty string if no requirements
        """
        requires_expr = test.get('requires', '')
        test_mode = test.get('mode', 'STD')

        # Add implicit requirement for COMP mode tests
        if test_mode == 'COMP':
            comp_requirement = 'C_EXTENSION>=1'
            if requires_expr:
                # Combine with existing requirement
                requires_expr = f'({requires_expr}) and {comp_requirement}'
            else:
                requires_expr = comp_requirement

        # Implicit RV32E_EN gating: a NON-benchmark test runs under RV32E
        # (RV32E_EN=1) ONLY if it explicitly mentions RV32E_EN in its requires
        # expression. Every other non-benchmark test is implicitly RV32I-only
        # (RV32E_EN==0), so the default regression never runs them under
        # -e_mode and existing hand-written asm tests (which name x16-x31) need
        # no edits.
        #
        # Benchmarks are EXEMPT from this implicit gate: they are C code, so the
        # toolchain ABI (-mabi=ilp32e under RV32E_EN=1) confines GCC to x0-x15
        # automatically -- they are base-ISA-agnostic and may legitimately run
        # under BOTH RV32I and RV32E without an explicit RV32E_EN requires.
        # (Caveat: the per-benchmark Makefile must propagate $MABI from
        # march_config.sh for the -e_mode build to assemble correctly.)
        #
        # NOTE: the substring check assumes RV32E_EN is the only rtl_config
        # parameter whose name contains 'RV32E_EN'. If a future parameter name
        # ever contains that substring, switch to a word-boundary regex match.
        is_benchmark = test.get('is_benchmark', False)
        if 'RV32E_EN' not in requires_expr and not is_benchmark:
            base_isa_requirement = 'RV32E_EN==0'
            if requires_expr:
                requires_expr = f'({requires_expr}) and {base_isa_requirement}'
            else:
                requires_expr = base_isa_requirement

        return requires_expr

    def _evaluate_requires(self, requires_expr: str, custom_rtl_values: Optional[dict] = None) -> bool:
        """
        Evaluate a requires expression against RTL configuration.

        Args:
            requires_expr: Boolean expression using RTL parameter names
            custom_rtl_values: Optional dictionary of custom RTL values to use instead of defaults

        Returns:
            True if requirement is satisfied, False otherwise
        """
        if not requires_expr:
            return True

        # Get RTL configuration values
        rtl_config = self._config.get('rtl_config', {})

        # Build a safe evaluation context with RTL parameter values
        context = {}
        for param_name, param_info in rtl_config.items():
            # Use custom value if provided, otherwise use default
            if custom_rtl_values and param_name in custom_rtl_values:
                context[param_name] = custom_rtl_values[param_name]
            else:
                context[param_name] = param_info.get('default', 0)

        # Safely evaluate the expression
        try:
            # Only allow simple comparison operators and logical operators
            # Replace parameter names with their values
            allowed_names = set(context.keys())
            allowed_names.update(['True', 'False', 'and', 'or', 'not'])

            # Evaluate in restricted context
            result = eval(requires_expr, {"__builtins__": {}}, context)
            return bool(result)
        except Exception as e:
            # If evaluation fails, log warning and assume requirement is met
            print(f"Warning: Failed to evaluate requires expression '{requires_expr}': {e}")
            return True

    def check_test_requirements(self, test_name: str, custom_rtl_values: Optional[dict] = None) -> tuple:
        """
        Check if a test's requirements are satisfied by the RTL configuration.
        Automatically adds C_EXTENSION>=1 requirement for COMP mode tests.

        Args:
            test_name: Name of the test
            custom_rtl_values: Optional dictionary of custom RTL values to check against

        Returns:
            Tuple of (requirements_met: bool, requires_expr: str or None)
        """
        for test in self.get_all_tests():
            if test['name'] == test_name:
                # Get full requirements expression (including implicit requirements)
                requires_expr = self._get_full_requires_expr(test)

                if requires_expr:
                    requirements_met = self._evaluate_requires(requires_expr, custom_rtl_values)
                    return (requirements_met, requires_expr)
                else:
                    return (True, None)
        # Test not found in config
        return (True, None)

    def get_rtl_config(self) -> Dict:
        """
        Get the RTL configuration.

        Returns:
            Dictionary of RTL configuration parameters
        """
        return self._config.get('rtl_config', {})

    def get_test_categories(self) -> tuple:
        """
        Categorize all tests into enabled, disabled, and skipped.
        Automatically applies C_EXTENSION>=1 requirement for COMP mode tests.

        Returns:
            Tuple of (enabled_tests, disabled_tests, skipped_tests)
            where each is a list of test dictionaries
        """
        enabled = []
        disabled = []
        skipped = []

        for test in self.get_all_tests():
            # Check if test is disabled
            if not test.get('enabled', True):
                disabled.append(test)
                continue

            # Check if test meets requirements (including implicit requirements)
            requires_expr = self._get_full_requires_expr(test)
            if requires_expr and not self._evaluate_requires(requires_expr):
                skipped.append(test)
                continue

            # Test is enabled and meets requirements
            enabled.append(test)

        return (enabled, disabled, skipped)

    def get_enabled_tests(self) -> List[Dict]:
        """
        Get all enabled tests from configuration, filtering by both
        enabled flag and requires expression.
        Automatically applies C_EXTENSION>=1 requirement for COMP mode tests.

        Returns:
            List of enabled test dictionaries that meet requirements
        """
        enabled = []
        for test in self.get_all_tests():
            # Check if test is enabled
            if not test.get('enabled', True):
                continue

            # Check if requirements are met (including implicit requirements)
            requires_expr = self._get_full_requires_expr(test)
            if requires_expr and not self._evaluate_requires(requires_expr):
                continue

            enabled.append(test)

        return enabled

    def get_test_info(self, test_name: str) -> Optional[Dict]:
        """
        Get full information for a test.

        Args:
            test_name: Name of the test

        Returns:
            Test dictionary or None if not found
        """
        for test in self._config.get('tests', []):
            if test['name'] == test_name:
                return test
        return None

    def get_modes_description(self) -> Dict[str, str]:
        """
        Get mode descriptions.

        Returns:
            Dictionary mapping mode names to descriptions
        """
        return self._config.get('modes', {})

    def is_no_random_irq(self, test_name: str) -> bool:
        """
        Check if a test has random IRQ injection disabled.

        Args:
            test_name: Name of the test

        Returns:
            True if random IRQ injection is disabled for this test
        """
        test_info = self.get_test_info(test_name)
        if test_info:
            return test_info.get('no_random_irq', False)
        return False

    def is_no_rsalu(self, test_name: str) -> bool:
        """
        Check if a test should skip variants containing random ALU stalls (-rsalu).

        Some tests rely on pipeline timing that is disrupted by random ALU stalls
        (e.g., fetch-stall HPM event: ALU stalls keep the pipeline full so
        ~id_instruction_valid never fires).

        Args:
            test_name: Name of the test

        Returns:
            True if -rsalu variants should be excluded for this test
        """
        test_info = self.get_test_info(test_name)
        if test_info:
            return test_info.get('no_rsalu', False)
        return False

    def is_no_rwsrom(self, test_name: str) -> bool:
        """
        Check if a test should skip variants containing random ROM wait states (-rwsrom).

        Some tests rely on pipeline timing that is disrupted by instruction-fetch
        wait states (e.g., LSU load-use hazard: ROM WS gives extra cycles for the
        first load to commit before the second reaches EX, suppressing the hazard).

        Args:
            test_name: Name of the test

        Returns:
            True if -rwsrom variants should be excluded for this test
        """
        test_info = self.get_test_info(test_name)
        if test_info:
            return test_info.get('no_rwsrom', False)
        return False

    def is_no_fahb(self, test_name: str) -> bool:
        """
        Check if a test should skip the fused AHB interconnect variant (-fahb).

        The fused interconnect absorbs the ROM and executable-SRAM AHB controllers
        and runs single-cycle by design, so the ROM/SRAM_X wait-state inserters
        are bypassed and any test that injects fixed/random ROM wait states (e.g.
        the fetch-stall HPM event test which forces 3-WS ROM) cannot exercise its
        intended pipeline-timing scenario in fused mode.

        Args:
            test_name: Name of the test

        Returns:
            True if -fahb variants should be excluded for this test
        """
        test_info = self.get_test_info(test_name)
        if test_info:
            return test_info.get('no_fahb', False)
        return False

    def is_no_variants(self, test_name: str) -> bool:
        """
        Check if a test should skip timing variants (no -all support).

        Args:
            test_name: Name of the test

        Returns:
            True if timing variants are disabled for this test
        """
        test_info = self.get_test_info(test_name)
        if test_info:
            return test_info.get('no_variants', False)
        return False

    def is_benchmark(self, test_name: str) -> bool:
        """
        Check if a test is a benchmark.

        Args:
            test_name: Name of the test

        Returns:
            True if test is marked as a benchmark, False otherwise
        """
        test_info = self.get_test_info(test_name)
        if test_info:
            return test_info.get('is_benchmark', False)
        return False

    def get_benchmark_pattern(self, test_name: str) -> Optional[str]:
        """
        Get the score extraction regex pattern for a benchmark test.

        Args:
            test_name: Name of the test

        Returns:
            Regex pattern string or None if not a benchmark
        """
        test_info = self.get_test_info(test_name)
        if test_info and test_info.get('is_benchmark', False):
            return test_info.get('score_pattern')
        return None

    def get_benchmark_metric(self, test_name: str) -> Optional[str]:
        """
        Get the metric name for a benchmark test.

        Args:
            test_name: Name of the test

        Returns:
            Metric name string or None if not a benchmark
        """
        test_info = self.get_test_info(test_name)
        if test_info and test_info.get('is_benchmark', False):
            return test_info.get('score_metric')
        return None

    def _sweep_configs(self, mode: str = "all") -> list:
        """The shared parameterization sweep set (default + corners + ofat +
        xprod for mode="all", or one of the other named modes from
        bin/rtl_sweep_configs.py:SWEEP_MODES). IDENTICAL set to
        `run_lint --sweep-mode <mode>`. Single source of truth:
        bin/rtl_sweep_configs.py."""
        rtl_config = self._config.get('rtl_config', {})
        if not rtl_config:
            return [("default", {})]
        _order, configs = generate_configs(sweepable_params(rtl_config), mode)
        return configs

    def get_rtl_config_combinations(self, mode: str = "all") -> Iterator[Tuple[str, Dict[str, int]]]:
        """Yield (label, {param: value}) for every config in the named
        sweep set (default: "all" — same set as `run_lint --sweep`).
        Free-valued params (e.g. MVENDORID) are not in the dict;
        generate_parameterization_file emits them at their default anyway."""
        for label, cfg in self._sweep_configs(mode):
            yield label, cfg

    def count_rtl_config_combinations(self, mode: str = "all") -> int:
        """Number of (de-duplicated) configs in the named sweep set."""
        return len(self._sweep_configs(mode))


def get_test_variants() -> List[List[str]]:
    """
    Get all test variant configurations (wait states, stalls, bus types).

    Environment Variables:
        REGRESSION_SINGLE_VARIANT: If set to "1", only run base variant (no timing variations)
                                   Useful for quick regression to check basic functionality

    Returns:
        List of command-line argument lists for each variant
    """
    # Check if single variant mode is requested
    single_variant = os.environ.get('REGRESSION_SINGLE_VARIANT', '0') == '1'

    if single_variant:
        # Return only the base variant (no timing variations)
        return [[]]

    variants = []

    # Base variants
    base_configs = [
        [],
        ['-rwsrom'                                ],
        [           '-rwsram'                     ],
        ['-rwsrom', '-rwsram'                     ],
        [                      '-rwsper'          ],
        ['-rwsrom',            '-rwsper'          ],
        [           '-rwsram', '-rwsper'          ],
        ['-rwsrom', '-rwsram', '-rwsper'          ],
        [                                 '-rsalu'],
        ['-rwsrom',                       '-rsalu'],
        [           '-rwsram',            '-rsalu'],
        ['-rwsrom', '-rwsram',            '-rsalu'],
        [                      '-rwsper', '-rsalu'],
        ['-rwsrom',            '-rwsper', '-rsalu'],
        [           '-rwsram', '-rwsper', '-rsalu'],
        ['-rwsrom', '-rwsram', '-rwsper', '-rsalu'],
    ]

    # Add variants without generic_ahb
    variants.extend(base_configs)

    # Add variants with generic_ahb
    for config in base_configs:
        variants.append(['-gahb'] + config)

    # Add random IRQ variants (2 extra scenarios):
    #   1. Random IRQ only (no other random stimuli)
    #   2. Random IRQ with all random stimuli active
    variants.append(['-rirq'])
    variants.append(['-rirq', '-rwsrom', '-rwsram', '-rwsper', '-rsalu'])

    # Add fused AHB variants (2 extra scenarios):
    #   1. Fused interconnect only (no other random stimuli)
    #   2. Fused interconnect with all random stimuli active
    # Note: -rwsrom is a no-op in fused mode (ROM controller absorbed, WS inserter
    # bypassed), but kept for symmetry with the rirq variants above.
    variants.append(['-fahb'])
    variants.append(['-fahb', '-rwsrom', '-rwsram', '-rwsper', '-rsalu'])

    return variants


def get_variant_log_suffix(variant_args: List[str]) -> str:
    """
    Generate log file suffix from variant arguments.

    Each suffix token mirrors its argument name (leading '-' stripped), so the
    log file name can be decoded by inspection without any lookup table.

    Args:
        variant_args: List of command-line arguments for the variant

    Returns:
        Suffix string for log file naming (e.g., '-gahb-rwsrom-rwsram-rsalu')
    """
    suffix_parts = []

    # Fixed order: gahb → fahb → rom → sram → periph → alu → irq
    for flag in ['-gahb',  '-fahb',
                 '-rwsrom', '-wsrom',
                 '-rwsram', '-wssram',
                 '-rwsper', '-wsper',
                 '-rsalu',  '-salu',
                 '-rirq']:
        if flag in variant_args:
            suffix_parts.append(flag[1:])   # strip leading '-'

    return '-' + '-'.join(suffix_parts) if suffix_parts else ''


if __name__ == '__main__':
    # Test the module
    config = TestConfig()
    print(f"Total tests: {len(config.get_all_tests())}")
    print(f"Enabled tests: {len(config.get_enabled_tests())}")
    print(f"Test variants: {len(get_test_variants())}")
