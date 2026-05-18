# =============================================================
# QuestaSim: Run ALL CAN RX Tests & Generate Merged Coverage
# =============================================================
# Usage:  vsim -c -do run_all_rx.do
# =============================================================

# --- Configuration ---
set test_list {
    can_rx_single_filter_test
    can_rx_dual_filter_test
    can_rx_masking_test
    can_rx_rejection_test
    can_rx_overrun_test
    can_rx_rmc_test
    can_rx_release_test
    can_rx_rtr_test
    can_rx_integrity_test
}

set cov_dir "coverage"

# --- 1. Clean up and setup library ---
if {[file exists work]} {
    vdel -all
}
vlib work

# --- 2. Compile RTL ---
vlog -cover bcs +incdir+../rtl/ +incdir+../bench/verilog/ \
     ../rtl/can_register_asyn.v \
     ../rtl/can_register_asyn_syn.v \
     ../rtl/can_register_syn.v \
     ../rtl/can_register.v \
     ../rtl/can_ibo.v \
     ../rtl/can_btl.v \
     ../rtl/can_bsp.v \
     ../rtl/can_acf.v \
     ../rtl/can_fifo.v \
     ../rtl/can_crc.v \
     ../rtl/can_registers.v \
     ../rtl/can_top.v

# --- 3. Compile UVM components ---
vlog -sv -cover bcs -suppress 13276 \
     +incdir+./wb_agent/ +incdir+./cb_agent/ +incdir+./seqs/ +incdir+./tests/ +incdir+./ \
     ./wb_agent/wb_can_if.sv \
     ./cb_agent/can_bus_if.sv \
     ./cb_agent/can_bus_agent_pkg.sv \
     ./wb_agent/wb_can_pkg.sv \
     ./wb_agent/can_tx_assertions.sv \
     ./top.sv

# --- Create output directories ---
file mkdir $cov_dir
file mkdir log

# --- 4. Run each test and save coverage ---
foreach test $test_list {
    echo "============================================================"
    echo "  RUNNING TEST: $test"
    echo "============================================================"

    # Start simulation session with -onfinish stop to prevent $finish from killing session
    vsim -onfinish stop -suppress 3829 -suppress 3009 -L work top \
         -l log/${test}.log \
         +UVM_TESTNAME=$test \
         -coverage

    # Run to completion
    run -all

    # Save coverage database
    coverage save ${cov_dir}/${test}.ucdb

    echo "  DONE: $test -> ${cov_dir}/${test}.ucdb"

    # Close simulation session (but stay in Questa)
    quit -sim
}

# --- 5. Merge all UCDB files ---
echo "============================================================"
echo "  MERGING COVERAGE FROM ALL RX TESTS"
echo "============================================================"

set ucdb_files {}
foreach test $test_list {
    if {[file exists ${cov_dir}/${test}.ucdb]} {
        lappend ucdb_files ${cov_dir}/${test}.ucdb
    }
}

if {[llength $ucdb_files] > 0} {
    eval vcover merge ${cov_dir}/can_rx_combined.ucdb $ucdb_files

    echo "GENERATING HTML REPORT..."
    vcover report -html -htmldir ${cov_dir}/html_report_rx \
            -details -source -annotate \
            ${cov_dir}/can_rx_combined.ucdb

    echo "GENERATING TEXT REPORT..."
    vcover report -details -all \
            -output log/coverage_summary_rx.txt \
            ${cov_dir}/can_rx_combined.ucdb
}

# --- 6. Print summary ---
echo ""
echo "============================================================"
echo "        CAN RX TEST SUITE - COMPLETE"
echo "============================================================"
echo "  Tests run   : [llength $test_list]"
echo "  Merged UCDB : ${cov_dir}/can_rx_combined.ucdb"
echo "  HTML Report : ${cov_dir}/html_report_rx/index.html"
echo "  Text Report : log/coverage_summary_rx.txt"
echo "============================================================"
echo "  Check individual log files in log/ for per-test results"
echo "============================================================"

quit -f
