# Batch script to run all CAN TX tests and merge coverage
# Optimized to run in a single Questa session

# 1. Setup
if [file exists work] { vdel -all }
vlib work

# 2. Compile RTL 
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

# 3. Compile UVM components
vlog -sv -cover bcs -suppress 13276 \
     +incdir+./wb_agent/ +incdir+./cb_agent/ +incdir+./seqs/ +incdir+./tests/ +incdir+./ \
     ./wb_agent/wb_can_if.sv \
     ./cb_agent/can_bus_if.sv \
     ./cb_agent/can_bus_agent_pkg.sv \
     ./wb_agent/wb_can_pkg.sv \
     ./wb_agent/can_tx_assertions.sv \
     ./top.sv

if {![file exists log]} { file mkdir log }
if {![file exists coverage]} { file mkdir coverage }

# -------------------------------------------------------------
# 4. RUN TESTS
# -------------------------------------------------------------

set tests {
    can_tx_sff_test
    can_tx_eff_test
    can_tx_rtr_test
    can_tx_dlc_rand_test
    can_tx_self_rx_test
    can_tx_single_shot_test
    can_tx_abort_test
    can_tx_data_integrity_test
    can_tx_burst_transmit_test
}

foreach test $tests {
    puts "=========================================================="
    puts "STARTING TEST: $test"
    puts "=========================================================="
    
    # Start simulation session
    vsim -suppress 3829 -suppress 3009 -L work top \
         -l log/${test}.log \
         +UVM_TESTNAME=$test \
         -coverage
         
    # Run to completion
    run -all
    
    # Save coverage database
    coverage save coverage/${test}.ucdb
    
    # Close simulation session
    quit -sim
}

# -------------------------------------------------------------
# 5. MERGE AND REPORT
# -------------------------------------------------------------
puts "MERGING COVERAGE DATABASES..."
# Build the merge command dynamically
set merge_cmd "vcover merge coverage/can_tx_combined.ucdb"
foreach test $tests {
    append merge_cmd " coverage/${test}.ucdb"
}
eval $merge_cmd

puts "GENERATING HTML REPORT..."
vcover report -details -html -htmldir coverage/html_report coverage/can_tx_combined.ucdb

puts "GENERATING TEXT REPORT..."
vcover report -details -file log/coverage_summary.txt coverage/can_tx_combined.ucdb

puts "DONE. Combined coverage report generated in log/coverage_summary.txt and coverage/html_report"
quit -f
