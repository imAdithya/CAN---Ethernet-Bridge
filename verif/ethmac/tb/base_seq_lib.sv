// tb/sequences/base_seq_lib.sv
`include "uvm_macros.svh"
import uvm_pkg::*;

class reg_write_seq extends uvm_sequence #(wishbone_transaction);
  `uvm_object_utils(reg_write_seq)

  rand bit [31:0] addr;
  rand bit [31:0] data;

  function new(string name = "reg_write_seq");
    super.new(name);
  endfunction

  virtual task body();
    wishbone_transaction req;
    req = wishbone_transaction::type_id::create("req");
    start_item(req);
    assert(req.randomize() with {
      address == local::addr;
      write_data == local::data;
      is_read == 1'b0;
      sel == 4'hf; // Full 32-bit write
    });
    finish_item(req);
  endtask : body

endclass : reg_write_seq

//-------------------------------------------------------------------------
// Sequence: Register Read
//-------------------------------------------------------------------------
class reg_read_seq extends uvm_sequence #(wishbone_transaction);
  `uvm_object_utils(reg_read_seq)

  rand bit [31:0] addr;
  bit [31:0] data;

  function new(string name = "reg_read_seq");
    super.new(name);
  endfunction

  virtual task body();
    wishbone_transaction req;
    wishbone_transaction rsp;
    
    req = wishbone_transaction::type_id::create("req");
    start_item(req);
    assert(req.randomize() with {
      address == local::addr;
      is_read == 1'b1;
      sel == 4'hf; // Full 32-bit read
    });
    finish_item(req);
    
    get_response(rsp);
assert(rsp != null)
  else `uvm_fatal("REG_READ", "No response received");

    data = rsp.read_data;
  endtask : body

endclass : reg_read_seq

//-------------------------------------------------------------------------
// Sequence: Configure the entire Ethernet MAC with default values
//-------------------------------------------------------------------------
class eth_config_seq extends uvm_sequence #(wishbone_transaction);
  `uvm_object_utils(eth_config_seq)
  `uvm_declare_p_sequencer(host_sequencer)

  reg_write_seq write_seq;

  // Register addresses
  localparam MODER_ADDR      = 32'h00;
  localparam IPGT_ADDR       = 32'h0C;
  localparam IPGR1_ADDR      = 32'h10;
  localparam IPGR2_ADDR      = 32'h14;
  localparam PACKETLEN_ADDR  = 32'h18;
  localparam COLLCONF_ADDR   = 32'h1C;
  localparam TX_BD_NUM_ADDR  = 32'h20;
  localparam MAC_ADDR0_ADDR  = 32'h40;
  localparam MAC_ADDR1_ADDR  = 32'h44;

  // Configuration values (can be randomized or set by the test)
  rand bit [47:0] mac_addr = 48'h00_11_22_33_44_55;
  rand int tx_bd_num = `ETH_TX_BD_NUM_DEF_0;

  function new(string name = "eth_config_seq");
    super.new(name);
  endfunction

  virtual task body();
    write_seq = reg_write_seq::type_id::create("write_seq");

    `uvm_info(get_type_name(), "Starting Ethernet MAC configuration sequence...", UVM_MEDIUM)

    // Set MAC Address
    write_seq.addr = MAC_ADDR1_ADDR; write_seq.data = mac_addr[15:0];  write_seq.start(m_sequencer);
    write_seq.addr = MAC_ADDR0_ADDR; write_seq.data = mac_addr[47:16]; write_seq.start(m_sequencer);

    // Set number of transmit buffer descriptors
    write_seq.addr = TX_BD_NUM_ADDR; write_seq.data = tx_bd_num; write_seq.start(m_sequencer);

    // Set packet lengths
    write_seq.addr = PACKETLEN_ADDR; write_seq.data = {16'd1518, 16'd64}; write_seq.start(m_sequencer);

    // Set collision configuration
    write_seq.addr = COLLCONF_ADDR; write_seq.data = {12'h0, `ETH_COLLCONF_DEF_2, 11'h0, `ETH_COLLCONF_DEF_0}; write_seq.start(m_sequencer);

    // Set inter-packet gaps
    write_seq.addr = IPGT_ADDR;  write_seq.data = `ETH_IPGT_DEF_0;  write_seq.start(m_sequencer);
    write_seq.addr = IPGR1_ADDR; write_seq.data = `ETH_IPGR1_DEF_0; write_seq.start(m_sequencer);
    write_seq.addr = IPGR2_ADDR; write_seq.data = `ETH_IPGR2_DEF_0; write_seq.start(m_sequencer);

    // Enable Tx and Rx
    write_seq.addr = MODER_ADDR; write_seq.data = 32'h0000_240B; write_seq.start(m_sequencer);

    `uvm_info(get_type_name(), "Ethernet MAC configuration sequence finished.", UVM_MEDIUM)
  endtask : body

endclass : eth_config_seq