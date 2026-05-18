# =============================================================
# QuestaSim: Run ALL CAN Tests & Generate Merged Coverage Report
# =============================================================
# Usage:  vsim -c -do run_complete_coverage.do
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
    can_rx_single_filter_test
    can_rx_dual_filter_test
    can_rx_masking_test
    can_rx_rejection_test
    can_rx_overrun_test
    can_rx_rmc_test
    can_rx_release_test
    can_rx_rtr_test
    can_rx_integrity_test
    can_tx_sff_test
    can_tx_eff_test
    can_tx_rtr_test
    can_tx_dlc_rand_test
    can_tx_self_rx_test
    can_tx_single_shot_test
    can_tx_abort_test
    can_tx_data_integrity_test
    can_tx_burst_transmit_test
    can_bit_stuff_test
    can_hard_sync_test
    can_resync_sjw_test
    can_arb_std_test
    can_arb_ext_test
    can_alc_capture_test
    can_ifs_test
    can_overload_test
    can_ecc_capture_test
    can_err_cnt_warning_test
    can_state_transition_test
    can_bus_off_recovery_test
    can_ack_error_test
    can_crc_error_test
    can_bit_error_test
    can_stuff_error_test
    can_form_error_test
    can_reactive_err_test
    can_gap_closer_test
}

set cov_dir "coverage_complete"

# --- Create coverage output directory ---
file mkdir $cov_dir
file mkdir log_complete

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

# --- 4. Run each test and save coverage ---
foreach test $test_list {
    puts "=========================================================="
    puts "  RUNNING TEST: $test"
    puts "=========================================================="

    vsim -voptargs="+acc" -coverage -suppress 3829 -suppress 3009 \
         -l log_complete/${test}.log \
         -onfinish stop -L work top \
         +UVM_TESTNAME=$test

    run -all

    coverage save ${cov_dir}/${test}.ucdb

    puts "  DONE: $test  ->  ${cov_dir}/${test}.ucdb"

    quit -sim
}

# --- 5. Merge all UCDB files ---
puts "=========================================================="
puts "  MERGING COVERAGE FROM ALL TESTS"
puts "=========================================================="

set ucdb_files {}
foreach test $test_list {
    lappend ucdb_files ${cov_dir}/${test}.ucdb
}

eval vcover merge ${cov_dir}/merged_complete.ucdb $ucdb_files

# --- 6. Generate HTML report ---
vcover report -html -htmldir ${cov_dir}/html_report \
        -details -source -annotate \
        ${cov_dir}/merged_complete.ucdb

# --- 7. Generate text summary ---
vcover report -details -all \
        -output ${cov_dir}/coverage_summary_complete.txt \
        ${cov_dir}/merged_complete.ucdb

# --- 8. Print summary ---
puts ""
puts "=========================================================="
puts "           COMBINED COVERAGE REPORT - COMPLETE"
puts "=========================================================="
puts "  Tests run   : [llength $test_list]"
puts "  Merged UCDB : ${cov_dir}/merged_complete.ucdb"
puts "  HTML Report : ${cov_dir}/html_report/index.html"
puts "  Text Report : ${cov_dir}/coverage_summary_complete.txt"
puts "=========================================================="

quit -f
