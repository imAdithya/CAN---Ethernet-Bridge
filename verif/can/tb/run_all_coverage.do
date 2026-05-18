# =============================================================
# QuestaSim: Run ALL WB Tests & Generate Merged Coverage Report
# =============================================================
# Usage:  vsim -c -do run_all_coverage.do
# =============================================================

# --- Configuration ---
set test_list {
    wb_can_single_access_test
    wb_can_burst_like_test
    wb_can_reset_stress_test
    wb_can_reg_access_test
    wb_can_reg_reset_test
    wb_can_reg_ro_test
    wb_can_reset_mode_lock_test
    wb_can_mode_switch_test
    wb_can_fifo_addr_map_test
    wb_can_clk_div_test
}

set cov_dir "coverage"

# --- Create coverage output directory ---
file mkdir $cov_dir

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

# --- 3. Compile UVM (WB agent only) ---
vlog -sv -cover bcs -suppress 13276 \
     +incdir+./wb_agent/ +incdir+./seqs/ +incdir+./tests/ +incdir+./ \
     ./wb_agent/wb_can_if.sv \
     ./wb_agent/wb_can_pkg.sv \
     ./top.sv

# --- 4. Run each test and save coverage ---
foreach test $test_list {
    echo "============================================================"
    echo "  RUNNING TEST: $test"
    echo "============================================================"

    # Save transcript log per test
    file mkdir log
    transcript file log/${test}.log

    vsim -voptargs="+acc" -coverage -suppress 3829 -suppress 3009 \
         -onfinish stop -L work top \
         +UVM_TESTNAME=$test

    run -all

    coverage save ${cov_dir}/${test}.ucdb

    echo "  DONE: $test  ->  ${cov_dir}/${test}.ucdb"
    echo "  LOG:  log/${test}.log"

    quit -sim
}

# --- 5. Merge all UCDB files ---
echo "============================================================"
echo "  MERGING COVERAGE FROM ALL TESTS"
echo "============================================================"

set ucdb_files {}
foreach test $test_list {
    lappend ucdb_files ${cov_dir}/${test}.ucdb
}

eval vcover merge ${cov_dir}/merged.ucdb $ucdb_files

# --- 6. Generate HTML report ---
vcover report -html -htmldir ${cov_dir}/html_report \
        -details -source -annotate \
        ${cov_dir}/merged.ucdb

# --- 7. Generate text summary ---
vcover report -details -all \
        -output ${cov_dir}/coverage_summary.txt \
        ${cov_dir}/merged.ucdb

# --- 8. Print summary ---
echo ""
echo "============================================================"
echo "           COMBINED COVERAGE REPORT - COMPLETE"
echo "============================================================"
echo "  Tests run   : [llength $test_list]"
echo "  Merged UCDB : ${cov_dir}/merged.ucdb"
echo "  HTML Report : ${cov_dir}/html_report/index.html"
echo "  Text Report : ${cov_dir}/coverage_summary.txt"
echo "============================================================"

quit -f
