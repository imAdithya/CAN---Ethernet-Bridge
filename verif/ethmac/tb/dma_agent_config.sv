// tb/uvm_components/dma_agent/dma_agent_config.sv
`include "uvm_macros.svh"
import uvm_pkg::*;

class dma_agent_config extends uvm_object;
  `uvm_object_utils(dma_agent_config)

  uvm_active_passive_enum is_active = UVM_PASSIVE;

  // CORRECT TYPE: This must be the MASTER interface
  virtual wishbone_master_if vif;

  function new(string name = "dma_agent_config");
    super.new(name);
  endfunction
endclass