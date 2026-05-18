# QuestaSim Run Script for CAN Testbench
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

# 4. Start simulation (using direct top for stability, with logging)
if {![file exists log]} {
    file mkdir log
}

# -------------------------------------------------------------
# UNCOMMENT THE DESIRED TEST TO RUN
# -------------------------------------------------------------

# --- TX-01: Standard Frame Format (SFF) ---
# vsim -c -suppress 3829 -suppress 3009 -L work top -l log/can_tx_sff_test.log +UVM_TESTNAME=can_tx_sff_test -do "run -all; quit -f"

# --- TX-02: Extended Frame Format (EFF) ---
# vsim -c -suppress 3829 -suppress 3009 -L work top -l log/can_tx_eff_test.log +UVM_TESTNAME=can_tx_eff_test -do "run -all; quit -f"

# --- TX-03: Remote Transmission Request (RTR) ---
# vsim -c -suppress 3829 -suppress 3009 -L work top -l log/can_tx_rtr_test.log +UVM_TESTNAME=can_tx_rtr_test -do "run -all; quit -f"

# --- TX-04: Data Length Code (DLC) Variation ---
# vsim -c -suppress 3829 -suppress 3009 -L work top -l log/can_tx_dlc_rand_test.log +UVM_TESTNAME=can_tx_dlc_rand_test -do "run -all; quit -f"

# --- TX-05: Self-Reception Request (SRR) ---
# vsim -c -suppress 3829 -suppress 3009 -L work top -l log/can_tx_self_rx_test.log +UVM_TESTNAME=can_tx_self_rx_test -do "run -all; quit -f"

# --- TX-06: Single Shot Transmission ---
# vsim -c -suppress 3829 -suppress 3009 -L work top -l log/can_tx_single_shot_test.log +UVM_TESTNAME=can_tx_single_shot_test -do "run -all; quit -f"

# --- TX-07: Transmission Abort ---
# vsim -c -suppress 3829 -suppress 3009 -L work top -l log/can_tx_abort_test.log +UVM_TESTNAME=can_tx_abort_test -do "run -all; quit -f"

# --- TX-08: Data Field Integrity ---
# vsim -c -suppress 3829 -suppress 3009 -L work top -l log/can_tx_data_integrity_test.log +UVM_TESTNAME=can_tx_data_integrity_test -do "run -all; quit -f"
vsim -voptargs="+acc" -c -do "run -all; exit" top +UVM_TESTNAME=can_rx_single_filter_test +UVM_VERBOSITY=UVM_LOW -wlf can_rx_single_filter_test.wlf

# --- TX-09: Burst Transmit ---
# vsim -c -suppress 3829 -suppress 3009 -L work top -l log/can_tx_burst_transmit_test.log +UVM_TESTNAME=can_tx_burst_transmit_test -do "run -all; quit -f"
