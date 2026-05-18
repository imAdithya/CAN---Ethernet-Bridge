`ifndef BRIDGE_PKG_SV
`define BRIDGE_PKG_SV

`include "can_eth_bridge_defines.v"

package bridge_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  // ETH MAC transaction (needed by host agent)
  `include "eth_transaction.sv"

  // Bridge-specific transactions
  `include "bridge_transaction.sv"

  // Reuse host agent from ETH MAC TB
  `include "host_agent_config.sv"
  `include "host_driver.sv"
  `include "host_monitor.sv"
  `include "host_sequencer.sv"
  `include "host_agent.sv"

  // CAN WB Agent
  `include "can_wb_agent_config.sv"
  `include "can_wb_driver.sv"
  `include "can_wb_monitor.sv"
  `include "can_wb_agent.sv"

  // Memory WB Agent
  `include "mem_wb_agent_config.sv"
  `include "mem_wb_driver.sv"
  `include "mem_wb_monitor.sv"
  `include "mem_wb_agent.sv"

  // Environment components
  `include "bridge_scoreboard.sv"
  `include "bridge_coverage.sv"
  `include "bridge_env.sv"

  // Sequences
  `include "bridge_reg_seq.sv"
  `include "bridge_filter_seq.sv"
  `include "bridge_upstream_seq.sv"

  // Tests
  `include "bridge_base_test.sv"
  `include "bridge_reg_access_test.sv"
  `include "bridge_reg_reset_test.sv"
  `include "filter_accept_test.sv"
  `include "filter_reject_test.sv"
  `include "counter_verify_test.sv"
  `include "mode_switch_test.sv"
  `include "bridge_disable_test.sv"

  // Upstream tests
  `include "upstream_basic_gw_test.sv"
  `include "upstream_eff_test.sv"
  `include "upstream_dlc_sweep_test.sv"
  `include "upstream_tunnel_test.sv"
  `include "upstream_filter_drop_test.sv"

  // Downstream sequences
  `include "bridge_downstream_seq.sv"

  // Downstream tests
  `include "downstream_basic_gw_test.sv"
  `include "downstream_bad_ethertype_test.sv"
  `include "downstream_bad_dlc_test.sv"
  `include "downstream_backpressure_test.sv"
  `include "downstream_bad_magic_test.sv"
  `include "downstream_tunnel_test.sv"

  // System-level sequences
  `include "bridge_system_seq.sv"

  // System-level tests
  `include "queue_fill_drain_test.sv"
  `include "arbiter_contention_test.sv"
  `include "sys_upstream_e2e_test.sv"
  `include "sys_downstream_e2e_test.sv"
  `include "sys_fullduplex_test.sv"
  `include "sys_fullduplex_stress_test.sv"

  // Reset tests
  `include "mid_transaction_reset_test.sv"

endpackage

`endif // BRIDGE_PKG_SV
