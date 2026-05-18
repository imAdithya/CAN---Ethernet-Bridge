`include "uvm_macros.svh"
import uvm_pkg::*;

class phy_packet_seq extends uvm_sequence #(ethernet_frame_transaction);
  `uvm_object_utils(phy_packet_seq)

  function new(string name="phy_packet_seq");
    super.new(name);
  endfunction

  virtual task body();
    req = ethernet_frame_transaction::type_id::create("req");
    start_item(req);

    // -------------------------------------------------
    // DEST MAC MUST MATCH ETH MAC REGISTERS
    // MAC = 12:34:56:78:9A:BC (network byte order, sent MSB first)
    // -------------------------------------------------
    req.dest_addr = '{8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07};

    // Source MAC (arbitrary)
    req.src_addr  = '{8'hAA, 8'hBB, 8'hCC, 8'hDD, 8'hEE, 8'hFF};

    // EtherType
    req.type_len  = 16'h0800;

    // -------------------------------------------------
    // Payload (50 bytes → MAC pads to 64)
    // -------------------------------------------------
    for (int i = 0; i < 50; i++)
      req.payload.push_back(i[7:0]);

    req.update_fcs(); // Calculate CRC

    finish_item(req);
  endtask
endclass
