// phy_max_packet_seq.sv - Generate maximum-length Ethernet packet
`include "uvm_macros.svh"
import uvm_pkg::*;

class phy_max_packet_seq extends uvm_sequence #(ethernet_frame_transaction);
  `uvm_object_utils(phy_max_packet_seq)

  function new(string name="phy_max_packet_seq");
    super.new(name);
  endfunction

  virtual task body();
    req = ethernet_frame_transaction::type_id::create("req");
    start_item(req);

    // Destination MAC (must match ETH MAC registers)
    req.dest_addr = '{8'h0A, 8'h0B, 8'h0C, 8'h0D, 8'h0E, 8'h0F};

    // Source MAC (arbitrary)
    req.src_addr  = '{8'hAA, 8'hBB, 8'hCC, 8'hDD, 8'hEE, 8'hFF};

    // EtherType
    req.type_len  = 16'h0800;

    // -------------------------------------------------
    // Maximum Payload: 1500 bytes
    // Total frame: 6 (dest) + 6 (src) + 2 (type) + 1500 (payload) + 4 (CRC) = 1518 bytes
    // -------------------------------------------------
    for (int i = 0; i < 1500; i++)
      req.payload.push_back(i[7:0]);

    req.update_fcs(); // Calculate CRC

    finish_item(req);
  endtask
endclass
