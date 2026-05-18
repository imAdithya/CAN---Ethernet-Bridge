`timescale 1ns/10ps

module top;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import wb_can_pkg::*;
  import can_bus_pkg::*;

  // Clock and reset
  bit clk;
  bit rst;

  // Clock generation: 25 MHz (40ns period)
  always #20 clk = ~clk;

  // Wishbone interface instance
  wb_can_if u_wb_if(.clk(clk), .rst(rst));

  // CAN bus interface instance
  cb_if u_can_if(.clk(clk), .rst(rst));

  // CAN bus logic - simplified since agent is removed
  wire can_tx_dut;           // DUT's TX output
  wire can_bus;              // The shared CAN bus

  // Default bus state to recessive (1)
  assign can_bus = can_tx_dut & u_can_if.can_rx;

  // Connect monitor observation point
  assign u_can_if.can_tx  = can_tx_dut;
  assign u_can_if.can_bus = can_bus;

  // CAN top instance with Wishbone interface
  can_top u_can_top(
    .wb_clk_i  (clk),
    .wb_rst_i  (rst),
    .wb_dat_i  (u_wb_if.din),
    .wb_dat_o  (u_wb_if.dout),
    .wb_cyc_i  (u_wb_if.cyc),
    .wb_stb_i  (u_wb_if.stb),
    .wb_we_i   (u_wb_if.we),
    .wb_adr_i  (u_wb_if.adr),
    .wb_ack_o  (u_wb_if.ack),
    .clk_i     (clk),
    .rx_i      (can_bus),            // CAN bus input
    .tx_o      (can_tx_dut),         // DUT's CAN TX output
    .bus_off_on(u_can_if.bus_off_on),
    .irq_on    (u_can_if.irq_on),
    .clkout_o  (u_wb_if.clkout)
  );

  // SVA Assertions for CAN TX Protocol
  can_tx_assertions u_tx_assertions (
    .clk     (clk),
    .rst     (rst),
    .tx_o    (can_tx_dut),
    .rx_i    (can_bus),
    .wb_we   (u_wb_if.we),
    .wb_addr (u_wb_if.adr),
    .wb_data (u_wb_if.din),
    .wb_stb  (u_wb_if.stb),
    .wb_ack  (u_wb_if.ack)
  );

  initial begin
    // Reset sequence
    rst = 1;
    // Initialize CAN RX to recessive
    u_can_if.can_rx = 1;
    #200;
    rst = 0;
  end

  initial begin
    // Pass Wishbone virtual interface to UVM
    uvm_config_db#(virtual wb_can_if)::set(null, "uvm_test_top", "vif", u_wb_if);
    uvm_config_db#(virtual wb_can_if)::set(null, "uvm_test_top.env.agt.driver", "vif", u_wb_if);
    uvm_config_db#(virtual wb_can_if)::set(null, "uvm_test_top.env.agt.monitor", "vif", u_wb_if);

    // Pass CAN Bus virtual interface to UVM via static handle
    can_bus_pkg::static_vif = u_can_if;

    run_test();
  end
endmodule
