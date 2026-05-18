# downstream_wave.do — Waveform for downstream_basic_gw_test

onerror {resume}
log -r /*

# ============================================================
# Clock & Reset
# ============================================================
add wave -divider "Clock & Reset"
add wave -label "wb_clk"    /tb_bridge_top/wb_clk
add wave -label "rst_n"     /tb_bridge_top/rst_n

# ============================================================
# Interrupt Signals
# ============================================================
add wave -divider "Interrupts"
add wave -label "eth_rx_irq"  /tb_bridge_top/mem_if/eth_rx_irq
add wave -label "can_tx_irq"  /tb_bridge_top/can_if/can_tx_irq

# ============================================================
# Downstream FSM State
# ============================================================
add wave -divider "Downstream FSM"
add wave -label "dn_state" -radix unsigned /tb_bridge_top/dut/u_downstream/state
add wave -label "dn_busy"  /tb_bridge_top/dut/u_downstream/busy

# ============================================================
# ETH WB Master Bus (Reading BD + RAM)
# ============================================================
add wave -divider "ETH Wishbone Bus (RAM Read)"
add wave -label "eth_wb_adr"   -radix hex /tb_bridge_top/mem_if/adr
add wave -label "eth_wb_dat_s" -radix hex /tb_bridge_top/mem_if/dat_s
add wave -label "eth_wb_cyc"   /tb_bridge_top/mem_if/cyc
add wave -label "eth_wb_stb"   /tb_bridge_top/mem_if/stb
add wave -label "eth_wb_we"    /tb_bridge_top/mem_if/we
add wave -label "eth_wb_ack"   /tb_bridge_top/mem_if/ack
add wave -label "word_cnt"     -radix unsigned /tb_bridge_top/dut/u_downstream/word_cnt
add wave -label "bd_cnt"       -radix unsigned /tb_bridge_top/dut/u_downstream/bd_cnt

# ============================================================
# Buffer Descriptor Registers
# ============================================================
add wave -divider "Buffer Descriptor"
add wave -label "rx_bd_status" -radix hex /tb_bridge_top/dut/u_downstream/rx_bd_status_reg
add wave -label "rx_bd_ptr"    -radix hex /tb_bridge_top/dut/u_downstream/rx_bd_ptr_reg

# ============================================================
# Validation
# ============================================================
add wave -divider "Validation"
add wave -label "rx_ethertype" -radix hex /tb_bridge_top/dut/u_downstream/rx_ethertype
add wave -label "rx_magic"     -radix hex /tb_bridge_top/dut/u_downstream/rx_magic
add wave -label "rx_version"   -radix hex /tb_bridge_top/dut/u_downstream/rx_version
add wave -label "frame_valid"  /tb_bridge_top/dut/u_downstream/frame_valid

# ============================================================
# Decapsulated CAN Frame (Output)
# ============================================================
add wave -divider "Decap CAN Frame"
add wave -label "rx_can_id"   -radix hex /tb_bridge_top/dut/u_downstream/rx_can_id
add wave -label "rx_can_dlc"  -radix unsigned /tb_bridge_top/dut/u_downstream/rx_can_dlc
add wave -label "rx_can_eff"  /tb_bridge_top/dut/u_downstream/rx_can_eff
add wave -label "rx_can_rtr"  /tb_bridge_top/dut/u_downstream/rx_can_rtr
add wave -label "rx_can_data" -radix hex /tb_bridge_top/dut/u_downstream/rx_can_data

# ============================================================
# CAN TX Queue
# ============================================================
add wave -divider "CAN TX Queue"
add wave -label "queue_push"  /tb_bridge_top/dut/u_downstream/queue_push
add wave -label "queue_pop"   /tb_bridge_top/dut/u_downstream/queue_pop
add wave -label "queue_full"  /tb_bridge_top/dut/u_downstream/queue_full
add wave -label "queue_empty" /tb_bridge_top/dut/u_downstream/queue_empty
add wave -label "queue_depth" -radix unsigned /tb_bridge_top/dut/u_downstream/queue_depth

# ============================================================
# CAN WB Master Bus (Writing to CAN controller)
# ============================================================
add wave -divider "CAN Wishbone Bus (CAN Write)"
add wave -label "can_wb_adr"   -radix hex /tb_bridge_top/can_if/adr
add wave -label "can_wb_dat_m" -radix hex /tb_bridge_top/can_if/dat_m
add wave -label "can_wb_cyc"   /tb_bridge_top/can_if/cyc
add wave -label "can_wb_stb"   /tb_bridge_top/can_if/stb
add wave -label "can_wb_we"    /tb_bridge_top/can_if/we
add wave -label "can_wb_ack"   /tb_bridge_top/can_if/ack
add wave -label "byte_cnt"     -radix unsigned /tb_bridge_top/dut/u_downstream/byte_cnt

# ============================================================
# Format
# ============================================================
configure wave -namecolwidth 180
configure wave -valuecolwidth 120
configure wave -timelineunits ns

run -all
wave zoom full
