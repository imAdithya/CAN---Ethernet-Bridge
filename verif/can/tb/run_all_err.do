# QuestaSim Run Script for CAN Error Management and Recovery Testbench
# Uses Siemens QuestaSim 2024.1 with built-in UVM

# 1. Clean up and setup libraries
if [file exists work] {
    vdel -all
}
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

# 4. Start simulation
if {![file exists log]} {
    file mkdir log
}
if {![file exists coverage]} {
    file mkdir coverage
}

# -------------------------------------------------------------
# RUN ALL ERROR MANAGEMENT TESTS (ERR-01 TO ERR-10)
# -------------------------------------------------------------

set tests {
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
    
    # Close simulation session without killing QuestaSim
    quit -sim
}

# 5. Merge Coverage and Generate Report
vcover merge coverage/can_err_combined.ucdb \
             coverage/can_ecc_capture_test.ucdb \
             coverage/can_err_cnt_warning_test.ucdb \
             coverage/can_state_transition_test.ucdb \
             coverage/can_bus_off_recovery_test.ucdb \
             coverage/can_ack_error_test.ucdb \
             coverage/can_crc_error_test.ucdb \
             coverage/can_bit_error_test.ucdb \
             coverage/can_stuff_error_test.ucdb \
             coverage/can_form_error_test.ucdb \
             coverage/can_reactive_err_test.ucdb

vcover report -html -htmldir log/coverage_err_html coverage/can_err_combined.ucdb
vcover report -file log/coverage_summary_err.txt coverage/can_err_combined.ucdb

puts "=========================================================="
puts "ALL ERR TESTS COMPLETED. Coverage saved to log/coverage_err_html"
puts "=========================================================="
