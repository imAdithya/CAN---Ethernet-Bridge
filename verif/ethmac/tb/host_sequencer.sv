// tb/uvm_components/host_agent/host_sequencer.sv
`include "uvm_macros.svh"
import uvm_pkg::*;

class host_sequencer extends uvm_sequencer #(wishbone_transaction);
  `uvm_component_utils(host_sequencer)

  virtual wishbone_slave_if vif;
  virtual wishbone_master_if mem_vif;
  uvm_event phy_rx_event;

  //-------------------------------------------------------------------------
  // Constructor
  //-------------------------------------------------------------------------
  function new(string name = "host_sequencer", uvm_component parent = null);
    super.new(name, parent);
  endfunction

endclass : host_sequencer