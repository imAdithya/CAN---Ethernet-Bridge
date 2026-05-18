`timescale 1ns/10ps

// CAN Bus Sequencer
class can_bus_sequencer extends uvm_sequencer #(cb_trans_debug);
  `uvm_component_utils(can_bus_sequencer)
  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction
endclass
