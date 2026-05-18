// tb/uvm_components/phy_agent/phy_sequencer.sv
`include "uvm_macros.svh"
import uvm_pkg::*;

class phy_sequencer extends uvm_sequencer #(ethernet_frame_transaction);
  `uvm_component_utils(phy_sequencer)

  //-------------------------------------------------------------------------
  // Constructor
  //-------------------------------------------------------------------------
  function new(string name = "phy_sequencer", uvm_component parent = null);
    super.new(name, parent);
  endfunction

endclass : phy_sequencer