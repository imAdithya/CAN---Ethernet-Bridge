`timescale 1ns/10ps

// CAN Bus Transaction Item (Enhanced with Data Payload)
class cb_trans_debug extends uvm_sequence_item;

  rand bit        ide;
  rand bit        rtr;
  rand bit [28:0] identifier;
  rand bit [3:0]  dlc;
  rand bit [7:0]  data[8]; // Max 8 bytes for Standard/Extended frames
  
  // Captures the entire unstuffed bitstream directly from the physical bus
  bit unstuffed_bits[$];
  
  // Track total number of unstuffed bits to mathematically prove payload size
  int unstuffed_bits_length;

  // Tag to distinguish between frames injected by the agent (RX) and sent by DUT (TX)
  bit is_rx;

  `uvm_object_utils(cb_trans_debug)

  function new(string name = "cb_trans_debug");
    super.new(name);
  endfunction

  constraint valid_dlc { dlc inside {[0:8]}; }

endclass
