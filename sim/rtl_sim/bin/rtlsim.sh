#!/bin/bash
#----------------------------------------------------------------------------
#          _    _           Family:    aRVern System IPs
#         / \__/ \          Script:    rtlsim.sh
#        /   /\   \         --------------------------------------------
#    ===/   /=========      Copyright: (c) 2026, aRVern-dev
#      /   / RV \   \       Contact:   arvernsilicon@gmail.com
#     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
#
# SPDX-License-Identifier: BSD-3-Clause
# Full license text is available in the LICENSE file at the repository root.
#----------------------------------------------------------------------------
# Bash wrapper invoked by runsim.py to call the selected RTL simulator.
#----------------------------------------------------------------------------

if [ $# -ne 10 ]; then
  echo "ERROR    : wrong number of arguments"
  echo "USAGE    : rtlsim.sh <top module>  <verilog stimulus file> <submit file>   <seed>  <rom-wait-state>  <sram-wait-state>  <periph-wait-state>  <alu_stall>     <AHB-type>  <inst-mode>"
  echo "Example  : rtlsim.sh tb_arvern   ./stimulus.v            ../../../bench/verilog/submit.f  123    ROM_RANDOM_WS     SRAM_ZERO_WS       PERIPH_WS            ALU_ZERO_STALL  HIPERF      STD_MODE"
  echo "VERILOG_SIMULATOR env keeps simulator name iverilog (default) / verilator / cver / verilog / ncverilog / vsim / vcs"
  exit 1
fi


###############################################################################
#                     Check if the required files exist                       #
###############################################################################

if [ ! -e $2 ]; then
    echo "Verilog stimulus file $2 doesn't exist"
    exit 1
fi
if [ ! -e $3 ]; then
    echo "Verilog submit file $3 doesn't exist"
    exit 1
fi


###############################################################################
#                         Start verilog simulation                            #
###############################################################################

# The bench writes its verdict (PASSED / FAILED / SKIPPED) to sim_result.txt;
# a run that wrote FAILED, or nothing at all, exits 1 even though $finish exits 0.
rm -f sim_result.txt
sim_status () {
    [ "$1" -ne 0 ] && return "$1"
    grep -qxE "PASSED|SKIPPED" sim_result.txt 2>/dev/null || return 1
    return 0
}

if [ "${VERILOG_SIMULATOR:-iverilog}" = iverilog ]; then

    rm -rf simv

    NODUMP=${SIMULATION_NODUMP-0}
    NOTRACE=${SIMULATION_NOTRACE-0}

    # Build defines based on environment variables
    DEFINES="-D SEED=$4 -D $5 -D $6 -D $7 -D ARV_VERIF_$8 -D $9 -D ${10} -D CHECKER_EN"

    if [ $NODUMP -eq 1 ]; then
        DEFINES="$DEFINES -D NODUMP"
    fi

    if [ $NOTRACE -eq 1 ]; then
        DEFINES="$DEFINES -D NOTRACE"
    fi

    # Add extra defines from environment (e.g., RANDOM_IRQ)
    if [ -n "${SIMULATION_EXTRA_DEFINES:-}" ]; then
        DEFINES="$DEFINES $SIMULATION_EXTRA_DEFINES"
    fi

    iverilog -o simv -s $1 -c $3 $DEFINES

    echo "Running simulation with: Icarus Verilog (iverilog)"
    echo "SIMULATION SEED: $4"

    if [[ $(uname -s) == CYGWIN* ]];
    then
     	vvp.exe ./simv
    else
        ./simv
    fi
    sim_status $?
    exit $?

elif [ "${VERILOG_SIMULATOR}" = verilator ]; then

    rm -rf obj_dir

    NODUMP=${SIMULATION_NODUMP-0}
    NOTRACE=${SIMULATION_NOTRACE-0}

    # Build defines
    DEFINES="-DSEED=$4 -D$5 -D$6 -D$7 -DARV_VERIF_$8 -D$9 -D${10} -DCHECKER_EN"
    if [ $NODUMP -eq 1 ]; then
        DEFINES="$DEFINES -DNODUMP"
    fi
    if [ $NOTRACE -eq 1 ]; then
        DEFINES="$DEFINES -DNOTRACE"
    fi
    # Extra defines arrive in Icarus's spaced form ("-D NAME"); Verilator only accepts
    # them attached ("-DNAME") and otherwise takes NAME as a source file name.
    if [ -n "${SIMULATION_EXTRA_DEFINES:-}" ]; then
        XD=""; want_name=0
        for tok in $SIMULATION_EXTRA_DEFINES; do
            if [ "$tok" = "-D" ]; then
                want_name=1
            elif [ $want_name -eq 1 ]; then
                XD="$XD -D$tok"; want_name=0
            else
                XD="$XD $tok"
            fi
        done
        DEFINES="$DEFINES $XD"
    fi

    # Verilator doesn't support nested -f includes, so flatten the file list
    FLATTENED_FILELIST=".verilator_filelist.f"
    FLATTEN_SCRIPT="${BIN_DIR:-../bin}/flatten_filelist.py"
    python3 ${FLATTEN_SCRIPT} $3 $FLATTENED_FILELIST

    if [ ! -f $FLATTENED_FILELIST ]; then
        echo "ERROR: Failed to flatten file list for Verilator"
        exit 1
    fi

    # Verilator compile options
    # --binary: Create standalone executable (Verilator 5.x+)
    # --timing: Enable timing support for delays
    # --trace: Enable VCD waveform tracing (unless NODUMP)
    # -Wno-fatal: Convert fatal warnings to warnings (for compatibility)
    # --top: Specify top module
    VERILATOR_OPTS="--binary --timing --x-initial unique -Wno-fatal --top $1"

    # Coverage (SIMULATION_COVERAGE=1, set by run_all -cov / run -cov). Each run drops
    # its coverage.dat into the shared pool named after the test+variant, so a whole
    # regression accumulates into one database.
    if [ "${SIMULATION_COVERAGE:-0}" = "1" ]; then
        VERILATOR_OPTS="$VERILATOR_OPTS --coverage-line"
        DEFINES="$DEFINES -DARV_COV_RESET_ZERO"   # tb_arvern.v zeroes the counters once reset is applied
        # Toggle is ~85% of the coverage points (one per BIT), and instrumenting it
        # dominates C++ compile time. SIMULATION_COV_TOGGLE=0 drops it when line+branch
        # is enough -- much faster, at the cost of the per-signal toggle view.
        if [ "${SIMULATION_COV_TOGGLE:-1}" = "1" ]; then
            # Toggle-cover signals of any width (Verilator skips those wider than 256 bits by default).
            VERILATOR_OPTS="$VERILATOR_OPTS --coverage-toggle --coverage-max-width 65536"
            # Corrected toggle macro for vectors wider than 64 bits (see cov_vlfix.py).
            python3 "$(dirname "${BASH_SOURCE[0]}")/cov_vlfix.py" obj_dir
        fi
        # The instrumented C++ dominates the build and each run simulates for well
        # under a second, so an unoptimised compile is the faster trade.
        VERILATOR_OPTS="$VERILATOR_OPTS -MAKEFLAGS OPT_FAST=-O0 -MAKEFLAGS OPT_SLOW=-O0 -MAKEFLAGS OPT_GLOBAL=-O0"
        # Instrument the DUT only (rtl/verilog): the testbench, the bench SoC IPs and the
        # memory models are not reported, and instrumenting them doubles the C++ to compile.
        # SIMULATION_COV_SCOPE=all instruments the whole bench.
        if [ "${SIMULATION_COV_SCOPE:-dut}" = "dut" ]; then
            COV_RTL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../rtl/verilog" && pwd)"
            # SIMULATION_COV_DIRS (absolute, space-separated) instruments other RTL instead,
            # e.g. an IP of the bench SoC seen through the core regression.
            python3 "$(dirname "${BASH_SOURCE[0]}")/cov_scope.py" cov_scope.vlt "$FLATTENED_FILELIST" ${SIMULATION_COV_DIRS:-$COV_RTL_DIR}
            VERILATOR_OPTS="$VERILATOR_OPTS cov_scope.vlt"
        fi
    fi

    # Add tracing if not disabled
    if [ $NODUMP -eq 0 ]; then
        VERILATOR_OPTS="$VERILATOR_OPTS --trace"
    fi

    # Compile with Verilator using flattened file list
    verilator $VERILATOR_OPTS -f $FLATTENED_FILELIST $DEFINES

    # Clean up temporary flattened file list
    rm -f $FLATTENED_FILELIST

    echo "Running simulation with: Verilator"
    echo "SIMULATION SEED: $4"

    # Run the generated executable
    if [ -f obj_dir/V$1 ]; then
        rm -f coverage.dat
        ./obj_dir/V$1 +verilator+rand+reset+1
        rc=$?
        if [ "${SIMULATION_COVERAGE:-0}" = "1" ] && [ -f coverage.dat ]; then
            mkdir -p "${SIMULATION_COV_DATS:-.}"
            mv coverage.dat "${SIMULATION_COV_DATS:-.}/cov_${SIMULATION_COV_TAG:-unknown}.dat"
        fi
        sim_status $rc
        exit $?
    else
        echo "ERROR: Verilator compilation failed - executable not found"
        exit 1
    fi

else

    NODUMP=${SIMULATION_NODUMP-0}
    NOTRACE=${SIMULATION_NOTRACE-0}

    # Build base defines
    vargs="+define+SEED=$4 -D $5 -D $6 -D $7 -D ARV_VERIF_$8 -D $9 -D ${10} +define+CHECKER_EN"

    if [ $NODUMP -eq 1 ]; then
        vargs="$vargs +define+NODUMP"
    fi

    if [ $NOTRACE -eq 1 ]; then
        vargs="$vargs +define+NOTRACE"
    fi

    if [ -n "${SIMULATION_EXTRA_DEFINES:-}" ]; then
        vargs="$vargs $SIMULATION_EXTRA_DEFINES"
    fi

   case $VERILOG_SIMULATOR in
    cver* )
       vargs="$vargs +define+VXL +define+CVER" ;;
    verilog* )
       vargs="$vargs +define+VXL" ;;
    ncverilog* )
       rm -rf INCA_libs
       vargs="$vargs +access+r +svseed=$4 +nclicq +define+TRN_FILE" ;;
    vcs* )
       rm -rf csrc simv*
       vargs="$vargs -lca -debug_access+all -sverilog +define+VPD_FILE" ;;
    vsim* )
       # Modelsim
       if [ -d work ]; then  vdel -all; fi
       vlib work
       echo "Running simulation with: Modelsim (vsim)"
       echo "SIMULATION SEED: $4"
       exec vlog +acc=prn -f $3 $vargs -R -c -do "run -all" ;;
    isim )
       # Xilinx simulator
       rm -rf fuse* isim*
       fuse $1 -prj $3 -o isim.exe -i ../../../bench/verilog/ -i ../../../rtl/verilog/
       echo "run all" > isim.tcl
       echo "Running simulation with: Xilinx ISim"
       echo "SIMULATION SEED: $4"
       ./isim.exe -tclbatch isim.tcl
       exit
   esac

   echo "Running simulation with: $VERILOG_SIMULATOR"
   echo "SIMULATION SEED: $4"
   exec $VERILOG_SIMULATOR -f $3 $vargs
fi
