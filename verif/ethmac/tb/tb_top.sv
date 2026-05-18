`include "uvm_macros.svh"
`include "timescale.v"
`include "wishbone_memory_model.sv"

import uvm_pkg::*;
import ethmac_pkg::*; // Import your package

module tb_top;

  // FIX 1: Remove the redundant wb_rst_i signal. The reset now lives inside the interface.
  logic wb_clk_i;
  logic mtx_clk_pad_i;
  logic mrx_clk_pad_i;

  // Configurable MII clock half-periods — stored in mii_if, read here
  // Default: 20ns → 25 MHz → 100 Mbps
  // 10 Mbps: 200ns → 2.5 MHz

  // --- Clock Generation ---
  initial begin
    wb_clk_i = 0;
    forever #5 wb_clk_i = ~wb_clk_i; // 100 MHz clock
  end

  initial begin
    mtx_clk_pad_i = 0;
    forever #(mii_if.mii_tx_half_period) mtx_clk_pad_i = ~mtx_clk_pad_i;
  end

  initial begin
    mrx_clk_pad_i = 0;
    forever #(mii_if.mii_rx_half_period) mrx_clk_pad_i = ~mrx_clk_pad_i;
  end

  initial begin
    wb_slave_if.rst = 1'b1;
    #50ns;
    wb_slave_if.rst = 1'b0;
  end

  // --- Interface Instantiation ---
  // FIX 2: Remove the .rst connection from this instantiation
  wishbone_slave_if  wb_slave_if ( .clk(wb_clk_i) );
  wishbone_master_if wb_master_if( .clk(wb_clk_i), .rst(wb_slave_if.rst) );
  mii_if             mii_if      ( .tx_clk(mtx_clk_pad_i), .rx_clk(mrx_clk_pad_i) );
  
  // Handle the bidirectional MDIO port
  wire dut_md_pad_o;
  assign mii_if.mdio = mii_if.mdio_oe ? dut_md_pad_o : 1'bz;


  // --- DUT Instantiation ---
  ethmac dut (
    // WISHBONE common
    .wb_clk_i(wb_clk_i),
    .wb_rst_i(wb_slave_if.rst),
    .wb_dat_i(wb_slave_if.dat_m),
    .wb_dat_o(wb_slave_if.dat_s),

    // WISHBONE slave
    .wb_adr_i(wb_slave_if.adr[11:2]),
    .wb_sel_i(wb_slave_if.sel),
    .wb_we_i (wb_slave_if.we),
    .wb_cyc_i(wb_slave_if.cyc),
    .wb_stb_i(wb_slave_if.stb),
    .wb_ack_o(wb_slave_if.ack),
    .wb_err_o(wb_slave_if.err),

    // WISHBONE master
    .m_wb_adr_o(wb_master_if.adr[31:0]),
    .m_wb_sel_o(wb_master_if.sel),
    .m_wb_we_o (wb_master_if.we),
    .m_wb_dat_o(wb_master_if.dat_m),
    .m_wb_dat_i(wb_master_if.dat_s),
    .m_wb_cyc_o(wb_master_if.cyc),
    .m_wb_stb_o(wb_master_if.stb),
    .m_wb_ack_i(wb_master_if.ack),
    .m_wb_err_i(wb_master_if.err),
    
    // WISHBONE B3 ports (tied off)
    .m_wb_cti_o(),
    .m_wb_bte_o(),

    // MII Transmit
    .mtx_clk_pad_i(mtx_clk_pad_i),
    .mtxd_pad_o   (mii_if.txd),
    .mtxen_pad_o  (mii_if.tx_en),
    .mtxerr_pad_o (mii_if.tx_err),

    // MII Receive
    .mrx_clk_pad_i(mrx_clk_pad_i),
    .mrxd_pad_i   (mii_if.rxd),
    .mrxdv_pad_i  (mii_if.rx_dv),
    .mrxerr_pad_i (mii_if.rx_err),
    .mcoll_pad_i  (mii_if.col),
    .mcrs_pad_i   (mii_if.crs),

    // MII Management
    .mdc_pad_o    (mii_if.mdc),      // MAC drives Clock
    .md_pad_o     (mii_if.mdio_o),   // MAC drives Data Out
    .md_padoe_o   (mii_if.mdio_oe),  // MAC drives Output Enable
    .md_pad_i     (mii_if.mdio_i),

    // Interrupt
    .int_o(wb_master_if.int_o)
  );

  assign mii_if.mdio = mii_if.mdio_oe ? mii_if.mdio_o : 1'bz;

  // 2. The MAC Input always reads the current state of the bus
  assign mii_if.mdio_i = mii_if.mdio;
  
  wishbone_memory_model mem_model ( .wb_if(wb_master_if.Slave) );
  

  // --- UVM Test Execution ---
  initial begin
    // This block is now correct and doesn't need changes.
    // It calls run_test() at time 0.
    uvm_config_db#(virtual wishbone_slave_if)::set(null, "uvm_test_top", "vif_slave", wb_slave_if);
    uvm_config_db#(virtual wishbone_master_if)::set(null, "uvm_test_top", "vif_master", wb_master_if);
    uvm_config_db#(virtual mii_if)::set(null, "uvm_test_top", "vif_mii", mii_if);
    uvm_config_db#(virtual wishbone_master_if)::set(null, "*", "mem_vif", wb_master_if);
    
    run_test();
  end

endmodule