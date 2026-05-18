// tb/uvm_components/phy_agent/phy_agent_config.sv
`include "uvm_macros.svh"
import uvm_pkg::*;

class phy_agent_config extends uvm_object;
  `uvm_object_utils(phy_agent_config)

  // Variable to control if the agent is active or passive
  uvm_event rx_frame_started;
  uvm_active_passive_enum is_active = UVM_ACTIVE;
  uvm_event collision_event = new();

  // >>> ADD THIS NEW FIELD AND CONSTRAINT <<<
  // Field used by HD sequences (e.g., tx_single_collision_seq) to track retries.
  rand int collisions_remaining;
  constraint c_collisions_remaining {
    // Max retransmission attempts is 16 per IEEE 802.3
    collisions_remaining inside {[0:16]};
  }

  // When set, drive_crs_during_tx() skips auto CRS management,
  // allowing the test sequence to control CRS directly.
  bit crs_override = 0;
  // >>> END ADDITION <<<

  // Virtual interface handle to connect to the physical signals
  virtual mii_if vif;

  //-------------------------------------------------------------------------
  // Constructor
  //-------------------------------------------------------------------------
  function new(string name = "phy_agent_config");
    super.new(name);
    rx_frame_started = new("rx_frame_started");
  endfunction

endclass