// tb/uvm_components/host_agent/host_agent_config.sv
`include "uvm_macros.svh"
import uvm_pkg::*;

class host_agent_config extends uvm_object;
  `uvm_object_utils(host_agent_config)

  uvm_active_passive_enum is_active = UVM_ACTIVE;

  // 1. Host Driver uses the SLAVE interface (Drives DUT Registers)
  virtual wishbone_slave_if vif; 

  // 2. Backdoor Access uses the MASTER interface (Accesses Memory Model)
  //    This is the field that was missing!
  virtual wishbone_master_if mem_vif;

  function new(string name = "host_agent_config");
    super.new(name);
  endfunction
endclass