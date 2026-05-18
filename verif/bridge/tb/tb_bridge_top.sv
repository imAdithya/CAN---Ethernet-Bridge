// tb_bridge_top.sv — Top-level testbench for CAN-Ethernet Bridge

`include "uvm_macros.svh"
`include "timescale.v"

import uvm_pkg::*;
import bridge_pkg::*;

module tb_bridge_top;

  // =========================================================================
  // Clock and Reset
  // =========================================================================
  logic wb_clk;
  logic rst_n;

  initial begin
    wb_clk = 0;
    forever #10 wb_clk = ~wb_clk;  // 50 MHz (matches TIMESTAMP_PRESCALE)
  end

  initial begin
    rst_n = 1'b0;
    #50ns;
    rst_n = 1'b1;
  end

  // =========================================================================
  // Interface Instantiation
  // =========================================================================
  wishbone_slave_if  host_wb_if (.clk(wb_clk));
  wishbone_master_if dummy_mem_if (.clk(wb_clk), .rst(~rst_n)); // For host_monitor backdoor
  can_wb_if          can_if     (.clk(wb_clk), .rst(~rst_n));
  mem_wb_if          mem_if     (.clk(wb_clk), .rst(~rst_n));

  // =========================================================================
  // Interrupt signals (driven by test sequences via force/release or config)
  // =========================================================================
  // Interrupts are now driven directly via the virtual interfaces from the test class
  initial begin
    can_if.can_rx_irq = 0;
    can_if.can_tx_irq = 0;
    mem_if.eth_tx_irq = 0;
    mem_if.eth_rx_irq = 0;
  end

  // =========================================================================
  // DUT Instantiation
  // =========================================================================
  can_eth_bridge_top dut (
    .clk          (wb_clk),
    .rst_n        (rst_n),

    // CAN WB Master (8-bit) → CAN agent
    .can_wbm_adr_o (can_if.adr),
    .can_wbm_dat_o (can_if.dat_m),
    .can_wbm_dat_i (can_if.dat_s),
    .can_wbm_cyc_o (can_if.cyc),
    .can_wbm_stb_o (can_if.stb),
    .can_wbm_we_o  (can_if.we),
    .can_wbm_ack_i (can_if.ack),

    // ETH WB Master (32-bit) → Memory agent
    .eth_wbm_adr_o (mem_if.adr),
    .eth_wbm_dat_o (mem_if.dat_m),
    .eth_wbm_dat_i (mem_if.dat_s),
    .eth_wbm_sel_o (mem_if.sel),
    .eth_wbm_cyc_o (mem_if.cyc),
    .eth_wbm_stb_o (mem_if.stb),
    .eth_wbm_we_o  (mem_if.we),
    .eth_wbm_ack_i (mem_if.ack),

    // Host WB Slave (32-bit) ← Host agent
    .host_wb_adr_i (host_wb_if.adr[7:0]),
    .host_wb_dat_i (host_wb_if.dat_m),
    .host_wb_dat_o (host_wb_if.dat_s),
    .host_wb_cyc_i (host_wb_if.cyc),
    .host_wb_stb_i (host_wb_if.stb),
    .host_wb_we_i  (host_wb_if.we),
    .host_wb_ack_o (host_wb_if.ack),

    // Interrupts
    .can_irq_i     (can_if.can_rx_irq),
    .eth_tx_irq_i  (mem_if.eth_tx_irq),
    .eth_rx_irq_i  (mem_if.eth_rx_irq),
    .can_tx_irq_i  (can_if.can_tx_irq)
  );

  // =========================================================================
  // Tie-offs: bridge DUT has no WB error output; tie err to 0
  // to prevent 'x' from breaking host_driver's while loop.
  // =========================================================================
  assign host_wb_if.err = 1'b0;

  // =========================================================================
  // Reset connection for host interface
  // =========================================================================
  initial begin
    host_wb_if.rst = 1'b1;
    #50ns;
    host_wb_if.rst = 1'b0;
  end

  // =========================================================================
  // Coverage Sampling — Hierarchical DUT signal access
  // Samples FSM states, filter results, frame fields, queue depth,
  // arbiter contention, and full-duplex activity every clock edge.
  // =========================================================================
  initial begin
    bridge_coverage cov_handle;
    // Wait for UVM to start and build components
    @(posedge wb_clk);
    forever begin
      @(posedge wb_clk);
      // Retrieve the coverage collector from the UVM config space
      if (uvm_config_db#(bridge_coverage)::get(null, "uvm_test_top.m_env", "m_coverage_handle", cov_handle)) begin
        cov_handle.sample_fsm_states(
          .up_state         (dut.u_upstream.state),
          .dn_state         (dut.u_downstream.state),
          .up_filter_drop_val(dut.u_upstream.filter_drop),
          .can_id           (dut.u_upstream.can_id_reg),
          .can_dlc          (dut.u_upstream.can_dlc_reg),
          .can_eff          (dut.u_upstream.can_eff_reg),
          .can_rtr          (dut.u_upstream.can_rtr_reg),
          .ethertype        (dut.u_downstream.rx_ethertype),
          .dlc_dn           (dut.u_downstream.rx_can_dlc),
          .frame_valid      (dut.u_downstream.frame_valid),
          .q_depth          (dut.u_downstream.u_queue.depth),
          .can_contention   (dut.u_arbiter.up_can_req & dut.u_arbiter.dn_can_req),
          .eth_contention   (dut.u_arbiter.up_eth_req & dut.u_arbiter.dn_eth_req)
        );
      end
    end
  end

  // =========================================================================
  // UVM Test Launch
  // =========================================================================
  initial begin
    uvm_config_db#(virtual wishbone_slave_if)::set(null, "uvm_test_top", "vif_host", host_wb_if);
    uvm_config_db#(virtual wishbone_master_if)::set(null, "uvm_test_top", "vif_host_mem", dummy_mem_if);
    uvm_config_db#(virtual can_wb_if)::set(null, "uvm_test_top", "vif_can", can_if);
    uvm_config_db#(virtual mem_wb_if)::set(null, "uvm_test_top", "vif_mem", mem_if);

    run_test();
  end

endmodule
