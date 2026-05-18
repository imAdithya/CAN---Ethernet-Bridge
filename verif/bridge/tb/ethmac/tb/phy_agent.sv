// tb/uvm_components/phy_agent/phy_agent.sv
`include "uvm_macros.svh"
import uvm_pkg::*;

class phy_agent extends uvm_agent;
  `uvm_component_utils(phy_agent)

  // Declare handles for the agent's components
  phy_driver    m_driver;
  phy_monitor   m_monitor;
  phy_sequencer m_sequencer;
  phy_agent_config m_config;

  //-------------------------------------------------------------------------
  // Constructor
  //-------------------------------------------------------------------------
  function new(string name = "phy_agent", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  //-------------------------------------------------------------------------
  // Build Phase: Create the agent's sub-components
  //-------------------------------------------------------------------------
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    
    // Get the configuration object from the config database
    if (!uvm_config_db#(phy_agent_config)::get(this, "", "config", m_config)) begin
      `uvm_fatal("CONFIG_LOAD", "Cannot get config object for phy_agent")
    end

    // Create the monitor
    m_monitor = phy_monitor::type_id::create("m_monitor", this);

    // Create the driver and sequencer only if the agent is active
    if (get_is_active() == UVM_ACTIVE) begin
      m_driver    = phy_driver::type_id::create("m_driver", this);
      m_sequencer = phy_sequencer::type_id::create("m_sequencer", this);
    end
  endfunction : build_phase

  //-------------------------------------------------------------------------
  // Connect Phase: Connect the driver and sequencer
  //-------------------------------------------------------------------------
// In phy_agent.sv connect_phase or build_phase
// Ensure m_driver.m_config points to the same object as m_config
function void connect_phase(uvm_phase phase);
  if (m_config.is_active == UVM_ACTIVE) begin
    m_driver.seq_item_port.connect(m_sequencer.seq_item_export);
    m_driver.m_config = m_config; // Direct handle assignment is safest
  end
endfunction

endclass : phy_agent