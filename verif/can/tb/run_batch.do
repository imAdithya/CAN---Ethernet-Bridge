# QuestaSim Batch Run Script - MERGED PACKAGE DEBUG
vdel -all -lib work
vlib work

# Compile UVM
vlog -sv -suppress 13276 \
     +incdir+./cb_agent/ +incdir+./wb_agent/ +incdir+./seqs/ +incdir+./tests/ +incdir+./ \
     ./cb_agent/can_bus_if.sv \
     ./wb_agent/wb_can_if.sv \
     ./wb_agent/wb_can_pkg.sv \
     ./top_minimal.sv

# Start sim
vsim -c -voptargs="+acc" -suppress 3829 -suppress 3009 \
     -L work top_minimal \
     +UVM_TESTNAME=wb_can_single_access_test \
     -do "run -all; quit -f"
