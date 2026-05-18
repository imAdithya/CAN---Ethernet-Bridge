`timescale 1ns/10ps
package can_bus_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  typedef virtual cb_if can_vif;
  
  // Static handle for VIF to avoid uvm_config_db issues in Questa
  can_vif static_vif;

  `include "can_bus_trans.sv"
  `include "can_bus_monitor.sv"
  `include "can_bus_sequencer.sv"
  `include "can_bus_driver.sv"
  `include "can_bus_agent.sv"
endpackage
