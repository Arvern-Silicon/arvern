<h1>
  <img src="img/aRVern_light.png" alt="aRVern" align="right" width="120">
  <br>
  aRVern Verification Guide
  <br clear="all">
</h1>

This guide is for verification engineers writing or extending the test corpus.
It covers the test architecture, the `.s` + `.v` pair convention, the test
registry in `run_config.json`, the regression policy (which tests run under
which variants), and a worked example of adding a new test from scratch.

For the broader simulation flow (`./run`, `./run_all`, `./run_lint`,
`./run_benchmark`), see [`simulation_guide.md`](simulation_guide.md).

---

## Table of Contents

1. [Test Architecture](#1-test-architecture)
2. [Test Naming Convention](#2-test-naming-convention)
3. [The `.s` + `.v` Pair](#3-the-s--v-pair)
4. [The `x31` Synchronisation Mechanism](#4-the-x31-synchronisation-mechanism)
5. [Registering a Test in `run_config.json`](#5-registering-a-test-in-run_configjson)
6. [Variant Matrix and Regression Policy](#6-variant-matrix-and-regression-policy)
7. [Worked Example — Writing a New Test](#7-worked-example--writing-a-new-test)
8. [C-Based Tests](#8-c-based-tests)
9. [Deviation-Lock Tests](#9-deviation-lock-tests)
10. [Coverage Philosophy](#10-coverage-philosophy)

---

## 1. Test Architecture

```
            ┌───────────────────────────────┐
            │      tb_arvern.v              │
            │  (the integrated testbench)   │
            │                               │
            │  ┌─────────┐    ┌──────────┐  │
            │  │ arvern  │◀──▶│ AHB SoC  │  │
            │  │  DUT    │    │ (ROM/RAM/│  │
            │  └─────────┘    │  periph) │  │
            │       ▲         └──────────┘  │
            │       │                       │
            │   probes_cpu.x31              │
            │       │                       │
            │  ┌────┴───────────────────┐   │
            │  │  <testname>.v          │   │
            │  │  (waits on x31,        │   │
            │  │   calls check_cpu_reg) │   │
            │  └────────────────────────┘   │
            └───────────────────────────────┘

            ┌────────────────────────────────┐
            │  <testname>.s                  │
            │  (firmware that runs on DUT,   │
            │   writes x31 sync values)      │
            └────────────────────────────────┘
```

The DUT runs a small program (the `.s` file, assembled to a hex image loaded
into ROM at reset). A *separate* testbench file (the `.v` file) watches the
DUT's architectural state via `probes_cpu.*` and checks expected values at
known synchronisation points.

The split is intentional: the firmware is what's being verified, the
testbench is the oracle. Neither side reads the other's source.

---

## 2. Test Naming Convention

Tests are named by extension / feature, with a stable prefix:

| Prefix | Covers |
|---|---|
| `inst_std_*` | Base RV32I instructions |
| `inst_m_*` | M-extension (mul/div) |
| `inst_zbb_*`, `inst_zba_*`, `inst_zbs_*`, `inst_zbc_*` | B-extension sub-extensions |
| `inst_zca_*`, `inst_zcb_*`, `inst_zcmp_*`, `inst_zcmt_*` | C-extension sub-extensions |
| `inst_csr_*` | CSR access / field-level edge cases |
| `inst_zicntr_*`, `inst_zihpm_*` | Counter CSRs |
| `inst_rv32e_*` | RV32E-specific (registers x16–x31 behaviour) |
| `trap_*` | Sync exceptions, IRQs, NMI delivery and return — split into `trap_excp_*`, `trap_irq_*`, `trap_wfi_*`, `trap_zcmp_*`, `trap_zcmt_*`, `trap_s_*` (S-mode), `trap_smrnmi_*` (Smrnmi) |
| `csr_*` | CSR field-level conformance |

The prefix carries a strong signal: a `trap_*` test exercises the trap FSM,
an `inst_*` test exercises a specific encoding, etc.

---

## 3. The `.s` + `.v` Pair

Each test is **exactly one** `.s` file and **exactly one** `.v` file with the
same base name, under `sim/rtl_sim/src/`:

```
sim/rtl_sim/src/inst_std_add.s
sim/rtl_sim/src/inst_std_add.v
```

Templates: [`TEST_TEMPLATE.s`](../sim/rtl_sim/src/TEST_TEMPLATE.s) and
[`TEST_TEMPLATE.v`](../sim/rtl_sim/src/TEST_TEMPLATE.v). They are intentionally
**not** registered in `run_config.json` so they never run in regression — copy
and rename when starting a new test.

### `.s` file (the firmware)

```asm
.section .text
.global main
main:
    jal t0, _random_irq_init    # enable random IRQ injection (omit for trap_* tests)
    li  t0, 0

    # 1. Initialise all registers to a known value (sentinel)
    li  x1,  0xFFFFFFFF
    li  x2,  0xFFFFFFFF
    # ...
    li  x31, 0xFFFFFFFF         # sync point: "init done"

    # 2. Perform the test operations
    li    x1, 10
    li    x2, 20
    add   x3, x1, x2            # result in x3

    # (optional intermediate sync points: 0x11111111, 0x22222222, …)

    li  x31, 0xdeadbeef         # final sync point: "test done"

end_of_test:
    nop
    j end_of_test               # hang here; the testbench ends sim
```

### `.v` file (the testbench / oracle)

```verilog
initial begin
    @(posedge free_clk);
    @(posedge hresetn);

    // (Optional) reset peripherals to a known state
    // ...

    // First sync point — verify init values
    @(probes_cpu.x31 == 32'hFFFFFFFF);
    check_cpu_reg(1, 32'hFFFFFFFF);
    // ...

    // Final sync point — verify results
    @(probes_cpu.x31 == 32'hdeadbeef);
    random_irq_enable = 0;       // disable random IRQs before final checks
    check_cpu_reg(1, 32'h0000000A);
    check_cpu_reg(3, 32'h0000001E);

    // End of test
    repeat(20) @(posedge free_clk);
    stimulus_done = 1;           // tells the harness to terminate
end
```

`check_cpu_reg(N, expected)` is a verification macro provided by the
testbench. It compares `probes_cpu.xN` with `expected` and counts pass/fail.

---

## 4. The `x31` Synchronisation Mechanism

The testbench cannot blindly check register values at random simulation
times — instructions execute on their own cadence, and timing variants stretch
that cadence unpredictably. **`x31` is reserved** as a synchronisation
channel between firmware and testbench:

| `x31` value | Convention |
|---|---|
| `0xFFFFFFFF` | "Init done" — initial sentinel after register init |
| `0x11111111`, `0x22222222`, … | Optional intermediate checkpoints |
| `0xdeadbeef` | "Test done" — final results ready |

The firmware writes the sync value to `x31` *after* the architectural state
it wants the testbench to inspect has been committed. The testbench
`@(probes_cpu.x31 == VALUE)` blocks until that exact value appears, then
performs its `check_cpu_reg` calls. This guarantees the testbench observes
the firmware's intended state.

**Rules:**
- Never store test results in `x31` — it's the sync channel only.
- `x31` is therefore unavailable as a general-purpose register in test code
  except as a sync-channel scratchpad.
- Disable random IRQ injection (`random_irq_enable = 0;`) before the final
  `check_cpu_reg` block — random IRQs can corrupt the read.

**RV32E exception:** in `-e_mode` x31 doesn't exist (the register file is
narrowed to x0–x15). RV32E tests use a different sync register (the templates
for RV32E tests should make this explicit).

---

## 5. Registering a Test in `run_config.json`

Add an entry to the `tests` array. Field reference:

| Field | Type | Required | Default | Effect |
|---|---|---|---|---|
| `name` | string | ✓ | — | Filename stem (`<name>.s` + `<name>.v` must exist under `src/` or `src-c/`) |
| `enabled` | bool | ✓ | — | Toggle without deleting |
| `mode` | `STD` / `COMP` / `BOTH` | ✓ | — | Which instruction-mode variants to build |
| `description` | string | ✓ | — | One-line note shown in regression reports |
| `requires` | string | optional | none | RTL-config gate. E.g. `C_EXTENSION>=1`, `NMI_EN==1`, `RV32E_EN==1`. Unmet → auto-skipped. |
| `no_random_irq` | bool | optional | `false` | Suppress random IRQ injection (use for timing-sensitive sequencing tests) |
| `no_variants` | bool | optional | `false` | Run only the base variant (skip the timing-variant matrix). For tests whose outcome is wait-state-dependent. |
| `no_rwsrom` | bool | optional | `false` | Skip the `-rwsrom` variant specifically |
| `no_fahb` | bool | optional | `false` | Skip the `-fahb` (fused-AHB) variant |
| `is_benchmark` | bool | optional | `false` | Marks as a benchmark — visible to `./run_benchmark`; enables score extraction |
| `score_metric` | string | optional | — | E.g. `"DMIPS/MHz"`, `"CoreMark/MHz"` — required for benchmarks |
| `score_pattern` | regex | optional | — | First capture group = numeric score — required for benchmarks |
| `optimization` | string | optional | global `-O3` | Override compiler `-O` level for this test |
| `toolchain` | string | optional | global active profile | Override toolchain profile for this test |

Sample entries:

```json
{
  "name": "inst_std_add",
  "mode": "BOTH",
  "enabled": true,
  "description": "ADD - Add"
},
{
  "name": "inst_zicntr_basic",
  "mode": "BOTH",
  "enabled": true,
  "description": "ZICNTR - cycle/instret/time + mcountinhibit",
  "requires": "ZICNTR_EN==1"
},
{
  "name": "trap_smrnmi_excp_preempt",
  "mode": "STD",
  "enabled": true,
  "no_variants": true,
  "description": "Accepted-deviation lock for NMI preempting in-flight posted store",
  "requires": "NMI_EN==1",
  "no_random_irq": true
}
```

The list is parsed by `bin/test_config.py`. Whatever you put in here is what
`./run_all` runs and what `./run` recognises as a valid testname.

---

## 6. Variant Matrix and Regression Policy

### Timing-variant flags

A test with `no_variants: false` is run by `./run_all` against every combination
of the timing-variant flags:

| Flag | Effect |
|---|---|
| `-rwsrom` | Random ROM wait states |
| `-rwsram` | Random SRAM wait states |
| `-rwsper` | Random peripheral wait states |
| `-rsalu` | Random ALU stalls |
| `-gahb` | Generic AHB interconnect (deeper) |
| `-fahb` | Fused-SRAM AHB controller variant |
| `-rirq` | Random IRQ injection |

The full matrix is ~36 variant combinations per test (configurable in
`test_config.py`). Total regression cost is therefore very roughly
`#tests × 36 × #iterations`.

### When to use `no_variants: true`

Use this **sparingly**. A test marked `no_variants: true` runs **only the base
variant** (no wait states, no random stalls, no random IRQs). It is appropriate
when:

- The test's correctness depends on a specific timing sequence that the
  random-stall variants would break (a "deviation lock" — see §9).
- The test would non-deterministically pass/fail under wait-state variation
  due to an accepted RTL deviation.
- The test specifically targets a base-variant-only race.

Misusing `no_variants` quietly drops test coverage. The convention is to
explain *why* in the `description` so the audit trail is clear.

### When to use `no_random_irq: true`

Random IRQ injection is fine for instruction-level tests because IRQs don't
change architectural results — `check_cpu_reg` just needs to see the final
state. But:

- **All `trap_*` tests** must set `no_random_irq: true` (or `no_variants`)
  because injecting a *random* IRQ on top of a *directed* IRQ test scrambles
  the expected sequence.
- Tests that race a specific event (counter sample, CSR read) also need it.

### When to use `requires:`

A test with `requires: "C_EXTENSION>=1"` is **auto-skipped** when the current
`rtl_config` (in the same `run_config.json`) doesn't satisfy the requirement.
This is how the regression remains green across the sweep: an RV32I-only
config simply skips all `inst_zca_*` tests instead of running and failing
them.

Supported operators in `requires:`: `==`, `>=`, `>`, `<=`, `<`, `&&`. See
`test_config.py:get_test_categories` for the parser.

---

## 7. Worked Example — Writing a New Test

Goal: verify the `XOR` instruction.

### Step 1 — Copy the templates

```bash
cd sim/rtl_sim/src
cp TEST_TEMPLATE.s inst_std_xor.s
cp TEST_TEMPLATE.v inst_std_xor.v
```

### Step 2 — Fill in the `.s` file

Replace the body of `inst_std_xor.s`:

```asm
.section .text
.global main
main:
    jal t0, _random_irq_init
    li  t0, 0

    # Init sentinels
    li  x1, 0xFFFFFFFF
    li  x2, 0xFFFFFFFF
    li  x3, 0xFFFFFFFF
    li  x31, 0xFFFFFFFF              # sync: init done

    # XOR test cases
    li  x1, 0xAAAAAAAA               # x1 = 0xAAAAAAAA
    li  x2, 0x55555555               # x2 = 0x55555555
    xor x3, x1, x2                   # x3 = 0xFFFFFFFF (all bits set)

    li  x4, 0xF0F0F0F0
    xor x5, x4, x4                   # x5 = 0 (self-XOR)

    li  x31, 0xdeadbeef              # sync: test done

end_of_test:
    nop
    j end_of_test
```

### Step 3 — Fill in the `.v` file

```verilog
initial begin
    @(posedge free_clk);
    @(posedge hresetn);

    @(probes_cpu.x31 == 32'hFFFFFFFF);
    check_cpu_reg(1, 32'hFFFFFFFF);
    check_cpu_reg(2, 32'hFFFFFFFF);
    check_cpu_reg(3, 32'hFFFFFFFF);

    @(probes_cpu.x31 == 32'hdeadbeef);
    random_irq_enable = 0;
    check_cpu_reg(1, 32'hAAAAAAAA);
    check_cpu_reg(2, 32'h55555555);
    check_cpu_reg(3, 32'hFFFFFFFF);
    check_cpu_reg(4, 32'hF0F0F0F0);
    check_cpu_reg(5, 32'h00000000);

    repeat(20) @(posedge free_clk);
    stimulus_done = 1;
end
```

### Step 4 — Register in `run_config.json`

Add to the `tests` array:

```json
{
  "name": "inst_std_xor",
  "mode": "BOTH",
  "enabled": true,
  "description": "XOR - Exclusive OR"
}
```

### Step 5 — Run the test

```bash
cd sim/rtl_sim/run
./run inst_std_xor              # std mode
./run inst_std_xor -c_mode      # comp mode
./run inst_std_xor -all         # full variant matrix (~36 variants)
```

If all variants pass, the test is good. If a specific variant fails,
investigate before merging — random wait states often expose latent race
conditions.

---

## 8. C-Based Tests

C-based tests live under `sim/rtl_sim/src-c/` (one sub-directory per test).
They consist of:

- `*.c` / `*.h` source
- A `startup.S` (the asm entry point that sets up `sp`, calls `main`, hangs
  on return)
- An `*.v` testbench (the oracle)

The same `x31` sync mechanism is used in C: the test ends with an asm block
that writes the sync value:

```c
asm volatile ("li x31, 0xdeadbeef");
while (1) { /* hang */ }
```

Benchmarks are registered with `is_benchmark: true` and a `score_pattern`
regex that extracts the printed score:

```json
{
  "name": "dhrystone_4mcu",
  "mode": "BOTH",
  "enabled": true,
  "is_benchmark": true,
  "score_metric": "DMIPS/MHz",
  "score_pattern": "DMIPS/MHz\\s*:\\s*([0-9.]+)",
  "description": "Dhrystone 2.1 — 4 mcu variant"
}
```

---

## 9. Deviation-Lock Tests

For each accepted deviation in `spec_compliance_notes.md`, there is (or should
be) a directed test that **locks in** the accepted behaviour — the test
*passes* when the deviation manifests and would *fail* only if the deviation
were "fixed" without updating the test.

Examples:

| Deviation | Lock-in test |
|---|---|
| NMI preempts in-flight posted store, fault dropped | `trap_smrnmi_excp_preempt.{s,v}` |
| `mcycle` freezes during WFI sleep | `inst_zicntr_cycle.v` (Phase 5 check) |
| RV32E x16–x31 read 0 / writes dropped | `inst_rv32e_xregs.{s,v}` |

These are nearly always `no_variants: true` because the deviation is
wait-state-dependent and only deterministic in the base variant. The
*purpose* of the test is the audit trail: "yes, this behaviour was
intentional as of <date>".

---

## 10. Coverage Philosophy

aRVern's verification corpus is **directed-test heavy**. There is no UVM,
no coverage-driven random stimulus. The approach:

1. **Per instruction**, at least one directed test exercises the encoding's
   typical behaviour.
2. **Per parameter / `requires:` value**, the regression sweep
   (`./run_all -rtl_sweep`) exercises every legal combination at least
   once.
3. **Per accepted deviation**, a deviation-lock test pins the behaviour
   (§9).
4. **Random stress** comes from the timing-variant matrix (wait states +
   random IRQs), not from random stimulus generation. Each directed test is
   re-run under randomised timing, surfacing race conditions.

The regression-summary report (`sim/rtl_sim/run/log/`) is the canonical view
of pass/fail counts. A "green" regression means every enabled test passed
every enabled variant — the bar for merging RTL changes.

---

## See Also

- [`simulation_guide.md`](simulation_guide.md) — how to actually run tests
- [`asphalt_trace_format.md`](asphalt_trace_format.md) — the per-instruction trace file format produced by every test run (column spec, annotations, snapshot layout); useful when writing custom checkers or oracle parsers
- [`traps_and_interrupts.md`](traps_and_interrupts.md) — what the `trap_*` tests cover
- [`spec_compliance_notes.md`](spec_compliance_notes.md) — the deviations that get lock-in tests
- `sim/rtl_sim/src/TEST_TEMPLATE.s` / `TEST_TEMPLATE.v` — copy-and-fill skeletons
- `sim/rtl_sim/run/run_config.json` — the test registry
- `sim/rtl_sim/bin/test_config.py` — registry parser, sweep generator
