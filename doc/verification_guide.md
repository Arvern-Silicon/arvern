<h1>
  <img src="img/aRVern_light.png" alt="aRVern" align="right" width="120">
  <br>
  aRVern Verification Guide
  <br clear="all">
</h1>

This guide is for verification engineers writing or extending the test corpus.
It covers the test architecture, the `.s` + `.v` pair convention, the bench
rules every test must follow, the test registry in `run_config.json`, the
regression policy (which tests run under which variants), and a worked example
of adding a new test from scratch.

For running tests (`./run`, `./run_all`, `./run_lint`, `./run_benchmark`,
logs, artefacts, debugging), see [`simulation_guide.md`](simulation_guide.md).

---

## Table of Contents

1. [Test Architecture](#1-test-architecture)
2. [Test Naming Convention](#2-test-naming-convention)
3. [The `.s` + `.v` Pair](#3-the-s--v-pair)
4. [The `x31` Synchronisation Mechanism](#4-the-x31-synchronisation-mechanism)
5. [Registering a Test in `run_config.json`](#5-registering-a-test-in-run_configjson)
6. [Variant Matrix and Regression Policy](#6-variant-matrix-and-regression-policy)
7. [Deterministic Error Injection — the `err_word` Hook](#7-deterministic-error-injection--the-err_word-hook)
8. [Worked Example — Writing a New Test](#8-worked-example--writing-a-new-test)
9. [C-Based Tests](#9-c-based-tests)
10. [Deviation-Lock Tests](#10-deviation-lock-tests)
11. [Coverage Philosophy](#11-coverage-philosophy)

---

## 1. Test Architecture

```
            ┌───────────────────────────────┐
            │      tb_arvern.v  (the bench) │
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
            │  │  (the stimulus: waits  │   │
            │  │   on x31, calls        │   │
            │  │   check_cpu_reg)       │   │
            │  └────────────────────────┘   │
            └───────────────────────────────┘

            ┌────────────────────────────────┐
            │  <testname>.s                  │
            │  (firmware that runs on DUT,   │
            │   writes x31 sync values)      │
            └────────────────────────────────┘
```

The DUT runs a small program (the `.s` file, assembled to a hex image loaded
into ROM at reset). A *separate* stimulus file (the `.v` file) watches the
DUT's architectural state via `probes_cpu.*` and checks expected values at
known synchronisation points. The firmware is what's being verified, the
stimulus is the oracle; neither side reads the other's source.

**How the `.v` is bound to the bench.** The runner installs the test `.v` as
`stimulus.v` and textually `` `include``s it into `tb_arvern.v`, after
`arv_parameterization.v` and `check_tasks.v`. That is why it has no
`module`/`endmodule`, why `free_clk`, `hresetn`, `stimulus_done`,
`random_irq_enable`, `error_on_exception`, `checker_enable`, `irq_m_*`/`irq_s_*`/
`irq_platform`, `use_aclint`/`use_plic`, `mtime_init`, `hartid`, `allow_deep_sleep`
and the `probes_cpu.*` hierarchy are reachable by name, why the RTL parameters are
visible as plain identifiers (`SU_MODE_EN ? … : …`), and why the
`integer ii, jj, kk, ahb_master, allow_peripheral_accesses;` header is a
convention rather than a requirement.

**Bench tasks** (`bench/verilog/check_tasks.v`): `check_cpu_reg(N, expected)`,
`check_mem_value(word_index, expected)`, `check_rom_value`,
`check_periph_reg_value`, `set_periph_regin_value`; `tb_error` counts a failure.
`check_mem_value` indexes `ahb_bus_system_inst.sram_x_inst.mem[]` by **word**,
i.e. `(byte_addr - 0x8000_0000) / 4` — hence the `` `define SPAD(byte_off) ((byte_off)/4)``
that tests reading the scratchpad carry.

**Bench checkers that fail a run without any check of yours:**

- `error_on_exception` (reset value 1): every synchronous exception the DUT takes
  counts as an error. A test that expects exceptions sets `error_on_exception = 0;`
  in its `.v`.
- The instruction/PC checker compares every instruction dispatched from ROM with
  the objdump listing (`checker_data.mem`); a PC not in the listing (jumping into
  `.word` data, executing the misaligned half of a 32-bit word) is an error, and
  40 of them abort the run. `checker_enable = 0;` disables it.

**Memory map** (`bench/verilog/ahb_decoder.v`, `bin/link.ld`):

| Region | Address | Use |
|---|---|---|
| ROM, 64 KB | `0x2000_0000` | `.text`; reset vector is `main`; the only region loaded from the image |
| Executable SRAM, 64 KB | `0x8000_0000` | Scratchpad, zeroed at time 0; `check_mem_value` reads it. A test can alias it over the unmapped space (§7, executable-SRAM alias) |
| Reserved in scratchpad | `0x8000_FF00` (handler stack, grows down), `0x8000_FFF0` (IRQ counter) | Used by `_random_irq_init`; keep test data below `0x8000_FE00` |
| Non-executable SRAM, 64 KB | `0x8100_0000` | Load/store only |
| Executable SRAM at 0, 4 KB | `0x0000_0000` | Arch-test flow only (`ARV_TB_SRAM_LO_X_EN`); unmapped in this flow, so address 0 is the faulting address the bus-error tests rely on — do not map or use it in a directed test |
| Peripherals #0–2 | `0x1004_0000`, `0x1004_1000`, `0x1004_2000` | `ahb_periph_example` (128 B each) |
| ACLINT / PLIC | `0x0200_0000` / `0x0C00_0000` | Enabled per test via `use_aclint` / `use_plic` |

No crt initialises `sp`; a test that uses the stack sets it (`li sp, 0x80010000`).
There is no `.data`: only ROM is loaded from the image, so constants go in `.text`
as `.word`, or are built with `li`/`sw`.

---

## 2. Test Naming Convention

Tests are named `inst_<ext>_*`, `trap_<area>_*`, `debug_<area>_*` or `csr_*`:

| Prefix | Covers |
|---|---|
| `inst_std_*` | Base RV32I instructions |
| `inst_m_*` | M-extension (mul/div) |
| `inst_zbb_*`, `inst_zba_*`, `inst_zbs_*`, `inst_zbc_*` | B-extension sub-extensions |
| `inst_zca_*`, `inst_zcb_*`, `inst_zcmp_*`, `inst_zcmt_*` | C-extension sub-extensions |
| `inst_csr_*` | CSR access / field-level edge cases |
| `inst_zicntr_*`, `inst_zihpm_*` | Counter CSRs |
| `inst_rv32e_*` | RV32E-specific (registers x16–x31 behaviour); run under `-e_mode` |
| `trap_*` | Sync exceptions, IRQs, NMI delivery and return — `trap_excp_*`, `trap_irq_*`, `trap_wfi_*`, `trap_zcmp_*`, `trap_zcmt_*`, `trap_s_*` (S-mode), `trap_priv_*`, `trap_m_*`, `trap_smrnmi_*` / `trap_nmi_*` (Smrnmi), `trap_pmp_*` (PMP / Smepmp), `trap_marv_*` / `trap_csr_*` |
| `debug_*` | External debug (RISC-V Debug 1.0): run control, entry, single-step, halt-on-reset — `debug_dmi_*` (DMI-driven DM: abstract GPR/CSR access, SBA), `debug_trig*` (Sdtrig), `debug_dtm_{uart,i2c,jtag}*` (end-to-end through the DTM) |
| `csr_*` | CSR field-level conformance |

The prefix carries a strong signal: a `trap_*` test exercises the trap FSM,
an `inst_*` test exercises a specific encoding. The `debug_dtm_uart`/`_i2c`/`_jtag`
prefixes are also a build switch: the runner compiles those tests with the
end-to-end DTM (`-D DTM_E2E -D DTM_<X>_E2E`) and the long watchdog.

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

### Rules every test must follow

1. **Boot rule for tests that install their own trap handler.** `mstatush.MDT`
   resets to 1 and `mnstatus.NMIE` to 0, so the first M-mode trap of a bare test
   is classified as unexpected and enters the critical-error state (`lockup_o`),
   never reaching the handler. Before the first trap can occur, execute
   `csrsi 0x744, 8` (NMIE = 1) **then** `csrw mstatush, x0` (MDT = 0), in that
   order — clearing MDT alone leaves every M-mode trap unexpected, and MIE cannot
   be set while MDT = 1. `_random_irq_init` performs this sequence; a test that
   omits `_random_irq_init` (every `trap_*` test) does it itself.
2. **Consume a load before signalling** (§4, load race).
3. **Drain posted stores before `check_mem_value`** (§4, store race).
4. **`wait()`, not `@()`, for the final sentinel** (§4).
5. **`error_on_exception = 0;`** in the `.v` of any test that expects a
   synchronous exception (§1).
6. **`random_irq_enable = 0;`** before the final `check_cpu_reg` block.
7. **Watchdog.** The bench kills a run after 50 ms of simulated time (50 000
   cycles). A `.v` may start with `` `define LONG_TIMEOUT`` (500 ms) or
   `` `define VERY_LONG_TIMEOUT`` (5 s); `-rirq` runs and `debug_dtm_*` tests get
   `LONG_TIMEOUT` automatically.
8. **PMP default-deny below M.** The regression default is `PMP_NR=16`, and a
   non-M access that matches no entry faults. Before dropping to S or U, invoke
   the `PMP_ALLOW_ALL` macro from `firmware_config.inc` (installs a permissive
   `pmpaddr0`/`pmpcfg0` rule; no-op when `CFG_PMP_NR == 0`).

### `.s` file (the firmware)

```asm
.section .text
.global main
main:
    jal t0, _random_irq_init    # enable random IRQ injection (omit for trap_* tests -- then apply rule 1)
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
    j end_of_test               # hang here; the stimulus ends sim
```

**Config-guarded firmware (`firmware_config.inc`).** A `.s` test that must
adapt to the active RTL configuration can `.include "firmware_config.inc"`, an
auto-generated GNU-`as` include with one `.equ CFG_<NAME>, <value>` per RTL
parameter (`CFG_SU_MODE_EN`, `CFG_C_EXTENSION`, `CFG_ZICNTR_EN`, …) and the
`PMP_ALLOW_ALL` macro (rule 8):

```asm
.include "firmware_config.inc"
.if CFG_SU_MODE_EN == 1
    csrw    sscratch, x0        # S-mode CSRs only exist on SU_MODE_EN=1 builds
.endif
```

Do not edit `firmware_config.inc` by hand; it is overwritten every run (how it
is generated: [`simulation_guide.md` §4.1](simulation_guide.md#41-the-run-command)).

**Controlling the encoding.** The same source is assembled with the standard or
the compressed `-march` according to the test's `mode` (§5); under `COMP` the
assembler compresses eligible instructions itself. A test that must pin an
encoding brackets it with `.option push` / `.option norvc` … `.option pop` and
emits explicit `.word` / `.2byte` values where needed (see the `inst_zcb_*` tests).
The same bracket is mandatory around a jump table at the reset vector that relies
on the default `marv_nmvec` / `mtvec` / `stvec` (`reset_vector + 4 / + 8 / + 12`):
under `COMP` a bare `j` becomes a 2-byte `c.j` and the slots no longer line up
(see `csr_ids.s`).

### `.v` file (the stimulus / oracle)

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
    wait(probes_cpu.x31 == 32'hdeadbeef);
    random_irq_enable = 0;       // disable random IRQs before final checks
    check_cpu_reg(1, 32'h0000000A);
    check_cpu_reg(3, 32'h0000001E);
    repeat(40) @(posedge free_clk);          // drain posted stores before memory checks
    check_mem_value(`SPAD(32'h00), 32'h0000001E);

    // End of test
    repeat(20) @(posedge free_clk);
    stimulus_done = 1;           // tells the harness to terminate
end
```

`check_cpu_reg(N, expected)` is a bench task (§1). It compares `probes_cpu.xN`
with `expected` and counts pass/fail. Under `-rirq` it blocks until
`mstatus.MIE = 1` and no load write-back is pending, so that it never samples
inside the random-IRQ handler (§6).

**Debug tests.** A `debug_*` test carries `requires: "DEBUG_EN==1"`; its `.v`
drives the DMI through the tasks in `bench/verilog/debug_dmi_tasks.v`
(`dmi_write`, `dmi_read`, `dm_halt`, `dm_resume`, `dm_reset_halt`,
`dm_set_resethaltreq`, `dm_ndmreset_pulse`, `sba_cfg`, `sba_write32`,
`sba_read32`, `sba_get_sberr`, …) and observes hart debug state through
`probes_debug`.

---

## 4. The `x31` Synchronisation Mechanism

The stimulus cannot blindly check register values at random simulation
times — instructions execute on their own cadence, and timing variants stretch
that cadence unpredictably. **`x31` is reserved** as a synchronisation
channel between firmware and stimulus:

| `x31` value | Convention |
|---|---|
| `0xFFFFFFFF` | "Init done" — initial sentinel after register init |
| `0x11111111`, `0x22222222`, … | Optional intermediate checkpoints |
| `0xdeadbeef` | "Test done" — final results ready |

The firmware writes the sync value to `x31` *after* the architectural state
it wants the stimulus to inspect has been committed. The stimulus blocks until
that exact value appears, then performs its checks.

> **Consume a load before signalling.** The stimulus samples registers as soon as `x31`
> changes, but `li x31, ...` has no dependency on a preceding load and retires while that
> load is still in its data phase. At base timing the write-back usually wins the race; with
> `-rwsram` it does not, and the stimulus reads a stale register. Put a consumer of the
> loaded value between the load and the sync write:
>
> ```asm
>     lw   a5, 0x00(s1)
>     addi t0, a5, 0          # forces the pipeline to wait for the write-back
>     li   x31, 0x22222222
> ```
>
> This class of bug is invisible to `run_all -fast`, which runs the base variant only.

> **Drain posted stores before reading memory.** The mirror image: `sw` followed by
> `li x31, …` retires the sync while the store is still in its AHB data phase; under
> `-rwsram` the stimulus's `check_mem_value` reads `sram_x_inst.mem[]` before the write
> lands. Before any `check_mem_value` after a sync, either `repeat(40) @(posedge free_clk);`
> in the `.v`, or have the firmware `lw` the stored word back and consume it before
> writing `x31`. Register checks need no drain.

> **`wait()`, not `@()`, for the final sentinel.** `@(probes_cpu.x31==VALUE)` is edge
> sensitive: if the firmware has already advanced past `VALUE` by the time the stimulus
> reaches the statement, it blocks forever. `wait(...)` returns immediately when the
> condition already holds. This bites most often on the last checkpoint, which the firmware
> typically follows with `li x31, 0xdeadbeef` a couple of instructions later.

**Rules:**
- Never store test results in `x31` — it's the sync channel only.
- Disable random IRQ injection (`random_irq_enable = 0;`) before the final
  `check_cpu_reg` block — random IRQs can corrupt the read.

**RV32E:** under `-e_mode` the register file is x0–x15, so `x31` does not exist.
RV32E tests use **x15 (a5)** as the sync register, use only x0–x15, and carry
`requires: "RV32E_EN==1"` (otherwise the implicit `RV32E_EN==0` gate, §5, keeps
them out of `-e_mode`). They call `_random_irq_init` exactly as an RV32I test does;
the runner links the ilp32e handler for them.

---

## 5. Registering a Test in `run_config.json`

Add an entry to the `tests` array. Field reference:

| Field | Type | Required | Default | Effect |
|---|---|---|---|---|
| `name` | string | ✓ | — | Filename stem (`<name>.s` + `<name>.v` under `src/`, or the directory `src-c/<name>/`) |
| `enabled` | bool | ✓ | — | Toggle without deleting |
| `mode` | `STD` / `COMP` / `BOTH` | ✓ | — | Which `-march` the source is assembled with (standard, compressed, or both as separate runs). `COMP` adds an implicit `C_EXTENSION>=1` requirement |
| `description` | string | ✓ | — | One-line note shown in regression reports |
| `requires` | string | optional | none | RTL-config gate; see below |
| `no_random_irq` | bool | optional | `false` | Drop the two `-rirq` variants — for every test that owns its trap handler or races a specific event |
| `no_variants` | bool | optional | `false` | Run only the base variant — for tests whose outcome is wait-state-dependent |
| `no_rwsrom` | bool | optional | `false` | Drop the `-rwsrom` variants — for tests that time instruction fetch |
| `no_rsalu` | bool | optional | `false` | Drop the `-rsalu` variants — for tests that time ALU completion |
| `no_fahb` | bool | optional | `false` | Drop the `-fahb` variants — for tests that depend on the default SRAM controller (e.g. the `err_word` hook, §7) |
| `variants` | `"light"` | optional | full matrix | `"light"`: run only the base variant and one variant with every random delay (`-rwsrom -rwsram -rwsper -rsalu`) in a full matrix or `-all` — for long walks whose purpose is register or address coverage, not pipeline timing |
| `is_benchmark` | bool | optional | `false` | Marks as a benchmark — visible to `./run_benchmark`; enables score extraction |
| `score_metric` | string | optional | — | E.g. `"DMIPS/MHz"`, `"CoreMark/MHz"` — required for benchmarks |
| `score_pattern` | regex | optional | — | First capture group = numeric score — required for benchmarks |
| `optimization` | string | optional | global `toolchain.build_config.OPTIMIZATION` (`-O2`) | Override compiler `-O` level for this test |
| `toolchain` | string | optional | global active profile | Override toolchain profile for this test |

`requires` is a Python boolean expression over the `rtl_config` parameter names:
`==`, `!=`, `<`, `<=`, `>`, `>=`, `and`, `or`, `not`, parentheses — e.g.
`"DEBUG_EN==1 and DM_TRIGGER_NR>=1"`. A malformed expression (`&&`, an unknown
name) is an error when the registry is loaded. Two gates are implicit: `mode: COMP`
adds `C_EXTENSION>=1`, and every non-benchmark test whose `requires` does not name
`RV32E_EN` gets `RV32E_EN==0`. Parser: `bin/test_config.py:_evaluate_requires`.

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
  "name": "trap_s_dbltrp_basic",
  "mode": "BOTH",
  "enabled": true,
  "description": "S DBLTRP   - Ssdbltrp happy path: HW sets sstatus.SDT on S trap entry",
  "requires": "SU_MODE_EN==1",
  "no_random_irq": true
}
```

The list is parsed by `bin/test_config.py`. Whatever you put in here is what
`./run_all` runs; `./run` also accepts an unregistered `src/` or `src-c/` test
and runs it in standard mode.

---

## 6. Variant Matrix and Regression Policy

### Timing-variant flags

| Flag | Effect |
|---|---|
| `-rwsrom` | Random ROM wait states |
| `-rwsram` | Random SRAM wait states |
| `-rwsper` | Random peripheral wait states |
| `-rsalu` | Random ALU stalls |
| `-gahb` | Generic AHB interconnect (deeper) |
| `-fahb` | Fused-SRAM AHB controller variant |
| `-rirq` | Random IRQ injection |

The matrix `./run_all` (and `./run <test> -all`) applies to a test is 36
variants, built in `bin/test_config.py`: the 16 combinations of
`{-rwsrom, -rwsram, -rwsper, -rsalu}`, each with and without `-gahb` (32), plus
`-rirq`, `-rirq` with all four wait/stall flags, `-fahb`, and `-fahb` with all
four. `-rirq` is therefore in only 2 of the 36 variants, and `no_random_irq`
costs almost nothing. Total regression cost is roughly `#tests × 36 × #iterations`.

### When to use `no_variants: true`

Use this **sparingly**. A test marked `no_variants: true` runs **only the base
variant** (no wait states, no random stalls, no random IRQs). It is appropriate
when:

- The test's correctness depends on a specific timing sequence that the
  random-stall variants would break (a wait-state-dependent deviation lock, §10).
- The test uses the `err_word` hook (§7).
- The test specifically targets a base-variant-only race.

Misusing `no_variants` quietly drops test coverage. Explain *why* in the
`description`. Prefer the narrower `no_rwsrom` / `no_rsalu` / `no_fahb` when
only one variant is incompatible.

### When to use `no_random_irq: true`

Random IRQ injection is fine for instruction-level tests because IRQs don't
change architectural results — `check_cpu_reg` just needs to see the final
state. But:

- **All `trap_*` tests** must set `no_random_irq: true` (or `no_variants`)
  because injecting a *random* IRQ on top of a *directed* IRQ test scrambles
  the expected sequence.
- Tests that race a specific event (counter sample, CSR read) also need it.
- Under `-rirq`, `check_cpu_reg` waits for `mstatus.MIE = 1` before sampling. A
  test that never sets MIE (no `_random_irq_init`) and is not `no_random_irq`
  hangs until the watchdog in the two `-rirq` variants.

### When to use `requires:`

A test with `requires: "C_EXTENSION>=1"` is **auto-skipped** in regression when
the current `rtl_config` doesn't satisfy it (a direct `./run` of it is an error).
This is how the regression remains green across the sweep: an RV32I-only
config simply skips all `inst_zca_*` tests instead of running and failing
them. Syntax and implicit gates: §5.

State the requirement the test actually has, not the feature it belongs to. A PMP test that
programs `pmpaddr4`/`pmpaddr5` needs `PMP_NR>=8`, not `PMP_NR>0` — at `PMP_NR=4` those
entries are read-only zero, so the rule silently fails to install and the test fails for a
reason that looks nothing like its cause. The personas build with fewer entries than the
regression default (`performance` 4, `ultra` 8, `light`/`classic` none), so a PMP test
that should run under a persona uses the low-numbered entries.

---

## 7. Deterministic Error Injection — the `err_word` Hook

The region-based error model (everything past `SRAM_X` errors) cannot express
two scenarios: a **single** erroring word whose successor is valid, and an
error whose 2-cycle AHB ERROR response must land on a **deterministic** cycle
alignment. The `err_word` hook in `bench/verilog/ahb_waitstate_inserter.v`
covers both. A test's `.v` stimulus arms it hierarchically:

```verilog
ahb_bus_system_inst.ahb_waitstate_inserter_sram_x_inst.err_word_addr = 32'h8000F004;
ahb_bus_system_inst.ahb_waitstate_inserter_sram_x_inst.err_word_ws   = 32'd3;
ahb_bus_system_inst.ahb_waitstate_inserter_sram_x_inst.err_word_en   = 1'b1;
```

A **read** of the armed word (compare on `[31:2]`; writes never match) is
squashed before the SRAM controller and answered with `err_word_ws` OKAY wait
cycles followed by the standard 2-cycle AHB ERROR. Disarmed (`err_word_en=0`,
the default), the hook is bit-inert — every modified expression reduces to its
original form, so no existing test is affected.

Restrictions: **base variant only** (`no_variants: true` is required for any
test using it) — `-fahb` removes the hooked inserter instance entirely, and
the random/fixed wait-state features share the same instance and are not
supported concurrently with an armed hook.

Users: `trap_excp_ifault_isolated_word.{s,v}`, `trap_excp_ifault_err_straddle.{s,v}`,
`debug_reset_halt_unfetchable.{s,v}` (ROM instance: the reset-vector fetch).

### Executable-SRAM alias

Address-walk tests need code and data at addresses the memory map never uses.
`ahb_bus_system_inst.sram_x_alias_en` (default 0) makes every address that selects
no slave and lies at or above `0x0000_1000` decode to the executable SRAM, which
uses only its low 16 address bits — so `0x0400_E000` reaches `0x8000_E000`. The
low 4 KB stay unmapped (address 0 remains the bus-error tests' faulting address).
Disarmed, the decoder is unchanged. The alias lives in the decoder, so it works in
every interconnect variant. User: `inst_pc_addr_walk.{s,v}`.

---

## 8. Worked Example — Writing a New Test

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

    wait(probes_cpu.x31 == 32'hdeadbeef);
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
./run inst_std_xor -all         # full 36-variant matrix
```

If all variants pass, the test is good. If a specific variant fails,
investigate before merging — random wait states often expose latent race
conditions. The build products (`pmem.lst`, `pmem.elf`), the VCD and
`asphalt.log` of the run are under `run/WORK/tmp*/` (symlinked from `run/`) until
the next run; see [`simulation_guide.md` §8](simulation_guide.md#8-waveforms-and-debugging).

### What a trap test adds

The XOR test needs none of the bench rules. A `trap_excp_*` test written from the
same templates additionally:

- omits `_random_irq_init`, installs `mtvec`, and runs the boot sequence of
  §3 rule 1 before anything can trap;
- sets `error_on_exception = 0;` in the `.v`;
- records what the handler saw (`mcause`, `mepc`, `mtval`) with `sw` to the
  scratchpad, and the `.v` reads it with `check_mem_value(`SPAD(off), …)` after a
  `repeat(40)` drain;
- is registered with `no_random_irq: true` and the `requires` its CSRs need
  (`SU_MODE_EN==1` for anything S-mode, `PMP_NR>=N` for PMP entries, …);
- invokes `PMP_ALLOW_ALL` before dropping to S or U.

---

## 9. C-Based Tests

A C test is the directory `sim/rtl_sim/src-c/<name>/`, containing:

- `*.c` / `*.h` source
- `startup.S` — the asm entry point that sets up `sp`, calls `main`, hangs on return
- `link.ld`
- `Makefile` — must source `run/march_config.sh` for `CC` / `MARCH` / `MABI` /
  `TC_OPT` (copy `hello_world/Makefile`)
- `<name>.v` — the stimulus

C tests do not use `x31`. Their `.v` watches the `ahb_periph_example` registers:
`periph0_reg_00_out` / `periph0_reg_01_out[0]` carry `putchar` output,
`periph1_reg_00_out[0]` brackets the timed region and `periph1_reg_01_out[0]`
marks program end (see `dhrystone_4mcu/dhrystone_4mcu.v`).

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

## 10. Deviation-Lock Tests

For each accepted deviation in `spec_compliance_notes.md`, there is (or should
be) a directed test that **locks in** the accepted behaviour — the test
*passes* when the deviation manifests and would *fail* only if the deviation
were "fixed" without updating the test.

Examples:

| Entry in `spec_compliance_notes.md` | Lock-in test |
|---|---|
| `mcycle` freezes during WFI sleep | `inst_zicntr_cycle.v` (Phase 5 check) |
| RV32E x16–x31 read 0 / writes dropped | `inst_rv32e_xregs.{s,v}` |
| WFI is not available to U-mode | `trap_wfi_umode.{s,v}` |
| Misaligned load/store into a PMP-denied region reports the access fault | `trap_pmp_misc.{s,v}` |
| Data-bus error reported as a resumable NMI, store not replayed | `trap_smrnmi_excp_preempt.{s,v}` (a pin NMI preempting the faulting store; the fault is still delivered, as a second RNMI) |

Use `no_variants: true` only when the locked behaviour is wait-state dependent
(e.g. `trap_smrnmi_excp_preempt`). The test pins the accepted behaviour; the
rationale lives in `spec_compliance_notes.md`.

---

## 11. Coverage Philosophy

aRVern's verification corpus is **directed-test heavy**. There is no UVM,
no coverage-driven random stimulus. The approach:

1. **Per instruction**, at least one directed test exercises the encoding's
   typical behaviour; the RISC-V arch-test suite adds encoding density
   ([`simulation_guide.md` §4.6](simulation_guide.md#46-arch-test-conformance-flow)).
2. **Per parameter**, the regression sweep (`./run_all -rtl_sweep`) exercises
   every legal value of every parameter at least once (one factor at a time),
   the LO/HI corners, the mul/div cross-products and the four reference personas;
   `requires` keeps each configuration's test list valid.
3. **Per accepted deviation**, a deviation-lock test pins the behaviour
   (§10).
4. **Random stress** comes from the timing-variant matrix (wait states +
   random IRQs), not from random stimulus generation. Each directed test is
   re-run under randomised timing, surfacing race conditions.
5. **Structural coverage** (line/branch/toggle, Verilator) is collected with
   `-cov` / `./run_cov` ([`simulation_guide.md` §4.5](simulation_guide.md#45-coverage)).

Two debug-suite notes that follow from this approach:

- `sbcs.sbbusyerror` (set by an `sbaddress0` write, an `sbdata0` write or an
  `sbdata0` read while `sbbusy=1`) is implemented but **defensive-only** in the
  suite: with no-wait-state memory the DMI poll interval outlasts a single AHB
  access, so `sbbusy` reads back 0 by the next transaction and the condition
  cannot be provoked deterministically. The `sberror`-suppression corollary is
  covered (`debug_dmi_sba`).
- `debug_dmi_wfi_read` is the negative control for the always-on APB-master rule
  (integration guide §10.3): a master clocked by the gated `hclk` deadlocks at
  the first transfer while the hart sleeps.

The regression summary (`sim/rtl_sim/run/log/summary.<N>.log`) is the canonical
view of pass/fail counts. A "green" regression means every enabled test passed
every enabled variant — the bar for merging RTL changes.

---

## See Also

- [`simulation_guide.md`](simulation_guide.md) — how to actually run tests
- [`asphalt_trace_format.md`](asphalt_trace_format.md) — the per-instruction trace file format produced by every test run (column spec, annotations, snapshot layout); useful when writing custom checkers or oracle parsers
- [`traps_and_interrupts.md`](traps_and_interrupts.md) — what the `trap_*` tests cover
- [`spec_compliance_notes.md`](spec_compliance_notes.md) — the deviations that get lock-in tests
- `sim/rtl_sim/src/TEST_TEMPLATE.s` / `TEST_TEMPLATE.v` — copy-and-fill skeletons
- `sim/rtl_sim/run/run_config.json` — the test registry
- `sim/rtl_sim/bin/test_config.py` — registry parser, variant matrix
