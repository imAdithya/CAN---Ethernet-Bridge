// tb/uvm_components/base/eth_transaction.sv
`include "uvm_macros.svh"
import uvm_pkg::*;
`include "ethmac_defines.v"

//-------------------------------------------------------------------------
// WISHBONE Transaction Class
//-------------------------------------------------------------------------
class wishbone_transaction extends uvm_sequence_item;
  `uvm_object_utils(wishbone_transaction)

  // Transaction fields
  rand bit [31:0] address;
  rand bit [31:0] write_data;
  bit  [31:0] read_data;
  rand bit is_read;
  rand bit [3:0] sel;

  // Metadata for scoreboard classification
  bit is_dma_txn;
  bit is_bd;
  bit is_tx_bd;
  bit is_rx_bd;

  // Constructor
  function new(string name = "wishbone_transaction");
    super.new(name);
  endfunction

  // Constraint to ensure valid byte enables
  constraint c_sel {
    sel != 4'b0000;
  }

  // ---- ADD THIS FUNCTION ----
  function void do_copy(uvm_object rhs);
    wishbone_transaction rhs_;
    if (!$cast(rhs_, rhs))
      `uvm_fatal("COPY_FAIL", "Type mismatch in do_copy for wishbone_transaction")

    this.address     = rhs_.address;
    this.write_data  = rhs_.write_data;
    this.read_data   = rhs_.read_data;
    this.is_read     = rhs_.is_read;
    this.sel         = rhs_.sel;
    this.is_dma_txn  = rhs_.is_dma_txn;
    this.is_bd       = rhs_.is_bd;
    this.is_tx_bd    = rhs_.is_tx_bd;
    this.is_rx_bd    = rhs_.is_rx_bd;
  endfunction

  // Utility function for easy printing
  function string convert2string();
    string s;
    s = $sformatf("WISHBONE Txn: %s Addr:0x%0h Sel:0x%0h",
                  is_read ? "READ " : "WRITE", address, sel);
    if (!is_read)
      s = {s, $sformatf(" Data:0x%0h", write_data)};
    else
      s = {s, $sformatf(" Data:0x%0h", read_data)};
    if (is_dma_txn) s = {s, " [DMA]"};
    if (is_tx_bd)   s = {s, " [Tx BD]"};
    if (is_rx_bd)   s = {s, " [Rx BD]"};
    return s;
  endfunction

endclass : wishbone_transaction



//-------------------------------------------------------------------------
// Ethernet Frame Transaction Class
//-------------------------------------------------------------------------
class ethernet_frame_transaction extends uvm_sequence_item;
  `uvm_object_utils(ethernet_frame_transaction)

  // Frame fields based on IEEE 802.3 standard
  rand byte unsigned dest_addr[$];
  rand byte unsigned src_addr[$];
  rand bit [15:0]    type_len;
  rand byte unsigned payload[$];
  rand bit [31:0]    fcs; // Frame Check Sequence

  // Constructor
  function new(string name = "ethernet_frame_transaction");
    super.new(name);
    // Default to a standard 6-byte MAC address size
    dest_addr.push_back(0); dest_addr.push_back(0); dest_addr.push_back(0);
    dest_addr.push_back(0); dest_addr.push_back(0); dest_addr.push_back(0);
    src_addr.push_back(0); src_addr.push_back(0); src_addr.push_back(0);
    src_addr.push_back(0); src_addr.push_back(0); src_addr.push_back(0);
  endfunction

  // Constraints for generating valid frames
  constraint c_mac_addr_size {
    dest_addr.size() == 6;
    src_addr.size() == 6;
  }

  constraint c_payload_size {
    // Ensure payload is between minimum and maximum Ethernet size
    payload.size() inside {[46:1500]};
  }

  // Calculate CRC-32 (Ethernet Standard)
  function void update_fcs();
    bit [31:0] crc;
    byte unsigned d;
    bit [31:0] poly = 32'hEDB88320;
    
    crc = 32'hFFFFFFFF;
    
    // Process Dest Addr
    foreach (dest_addr[i]) begin
      d = dest_addr[i];
      crc = update_crc_byte(crc, d, poly);
    end
    
    // Process Src Addr
    foreach (src_addr[i]) begin
      d = src_addr[i];
      crc = update_crc_byte(crc, d, poly);
    end
    
    // Process Type/Len
    d = type_len[15:8]; crc = update_crc_byte(crc, d, poly);
    d = type_len[7:0];  crc = update_crc_byte(crc, d, poly);
    
    // Process Payload
    foreach (payload[i]) begin
      d = payload[i];
      crc = update_crc_byte(crc, d, poly);
    end
    
    this.fcs = ~crc; 
  endfunction

  function bit [31:0] update_crc_byte(bit [31:0] crc, byte data, bit [31:0] poly);
    bit [31:0] c;
    c = crc ^ data;
    repeat (8) begin
      if (c[0]) c = (c >> 1) ^ poly;
      else      c = (c >> 1);
    end
    return c;
  endfunction

endclass : ethernet_frame_transaction