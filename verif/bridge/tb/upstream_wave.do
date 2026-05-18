# upstream_wave.do — Simplified waveform for upstream_basic_gw_test

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
add wave -label "can_rx_irq"  /tb_bridge_top/can_if/can_rx_irq
add wave -label "eth_tx_irq"  /tb_bridge_top/mem_if/eth_tx_irq

# ============================================================
# Upstream FSM State
# ============================================================
add wave -divider "Upstream FSM"
add wave -label "up_state" -radix unsigned /tb_bridge_top/dut/u_upstream/state
add wave -label "up_busy"  /tb_bridge_top/dut/u_upstream/busy

# ============================================================
# CAN Frame Data (Input — read from CAN controller)
# ============================================================
add wave -divider "CAN Frame Input"
add wave -label "frame_info"  -radix hex /tb_bridge_top/dut/u_upstream/frame_info_reg
add wave -label "can_id"      -radix hex /tb_bridge_top/dut/u_upstream/can_id_reg
add wave -label "can_dlc"     -radix unsigned /tb_bridge_top/dut/u_upstream/can_dlc_reg
add wave -label "can_eff"     /tb_bridge_top/dut/u_upstream/can_eff_reg
add wave -label "can_rtr"     /tb_bridge_top/dut/u_upstream/can_rtr_reg
add wave -label "can_data"    -radix hex /tb_bridge_top/dut/u_upstream/can_data_reg

# ============================================================
# CAN WB Master Bus (Reading CAN registers)
# ============================================================
add wave -divider "CAN Wishbone Bus"
add wave -label "can_wb_adr"   -radix hex /tb_bridge_top/can_if/adr
add wave -label "can_wb_dat_s" -radix hex /tb_bridge_top/can_if/dat_s
add wave -label "can_wb_dat_m" -radix hex /tb_bridge_top/can_if/dat_m
add wave -label "can_wb_cyc"   /tb_bridge_top/can_if/cyc
add wave -label "can_wb_stb"   /tb_bridge_top/can_if/stb
add wave -label "can_wb_we"    /tb_bridge_top/can_if/we
add wave -label "can_wb_ack"   /tb_bridge_top/can_if/ack
add wave -label "byte_cnt"     -radix unsigned /tb_bridge_top/dut/u_upstream/byte_cnt

# ============================================================
# Filter Signals
# ============================================================
add wave -divider "Filter"
add wave -label "filter_en"    /tb_bridge_top/dut/u_upstream/u_filter/filter_en
add wave -label "filter_mode"  /tb_bridge_top/dut/u_upstream/u_filter/filter_mode
add wave -label "filter_check" /tb_bridge_top/dut/u_upstream/filter_check
add wave -label "raw_hit"      /tb_bridge_top/dut/u_upstream/u_filter/raw_hit
add wave -label "filter_drop"  /tb_bridge_top/dut/u_upstream/filter_drop

# ============================================================
# Encapsulated Frame Output (Written to RAM)
# ============================================================
add wave -divider "Encap Frame Output"
add wave -label "tx_frame_len" -radix unsigned /tb_bridge_top/dut/u_upstream/tx_frame_len
add wave -label "frame_words"  -radix unsigned /tb_bridge_top/dut/u_upstream/frame_words
add wave -label "word_cnt"     -radix unsigned /tb_bridge_top/dut/u_upstream/word_cnt

# ============================================================
# ETH WB Master Bus (Writing to RAM & BD)
# ============================================================
add wave -divider "ETH Wishbone Bus (RAM Write)"
add wave -label "eth_wb_adr"   -radix hex /tb_bridge_top/mem_if/adr
add wave -label "eth_wb_dat_m" -radix hex /tb_bridge_top/mem_if/dat_m
add wave -label "eth_wb_sel"   -radix hex /tb_bridge_top/mem_if/sel
add wave -label "eth_wb_cyc"   /tb_bridge_top/mem_if/cyc
add wave -label "eth_wb_stb"   /tb_bridge_top/mem_if/stb
add wave -label "eth_wb_we"    /tb_bridge_top/mem_if/we
add wave -label "eth_wb_ack"   /tb_bridge_top/mem_if/ack

# ============================================================
# Format waveform display
# ============================================================
configure wave -namecolwidth 180
configure wave -valuecolwidth 120
configure wave -timelineunits ns

run -all
wave zoom full
