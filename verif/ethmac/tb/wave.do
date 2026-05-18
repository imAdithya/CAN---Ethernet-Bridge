# wave.do - Excessive Defer Hardware Bug Proof

# Clear default signals
delete wave *

# Add only the 6 debug signals
add wave -noupdate -divider "EXCESSIVE DEFER BUG"
add wave -noupdate -radix hex    -label "1_NibCnt"         /tb_top/dut/txethmac1/txcounters1/NibCnt
add wave -noupdate               -label "2_ExcessiveDefer" /tb_top/dut/txethmac1/txcounters1/ExcessiveDefer
add wave -noupdate               -label "3_TxAbort_int"    /tb_top/dut/txethmac1/TxAbort
add wave -noupdate               -label "4_TxStartFrmIn"   /tb_top/dut/maccontrol1/TxStartFrmIn
add wave -noupdate               -label "5_TxAbortOut"     /tb_top/dut/maccontrol1/TxAbortOut
add wave -noupdate               -label "6_StateDefer"     /tb_top/dut/txethmac1/txstatem1/StateDefer

log -r /*
run -all
wave zoom full