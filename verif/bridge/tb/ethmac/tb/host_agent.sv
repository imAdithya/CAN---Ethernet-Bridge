// tb/uvm_components/host_agent/host_agent.sv
`include "uvm_macros.svh"
import uvm_pkg::*;

class host_agent extends uvm_agent;
  `uvm_component_utils(host_agent)

  host_driver    m_driver;
  host_monitor   m_monitor;
  host_sequencer m_sequencer;
  
  host_agent_config m_config; 

  function new(string name = "host_agent", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  // -----------------------------------------------------------------------
  // BUILD PHASE
  // -----------------------------------------------------------------------
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    // 1. GET CONFIG FIRST (This must be first!)
    if (!uvm_config_db#(host_agent_config)::get(this, "", "config", m_config)) begin
      `uvm_fatal("CONFIG_LOAD", "Cannot get config object for host_agent")
    end

    // 2. CHECK MEMORY INTERFACE (Now safe to check m_config)
    if (m_config.mem_vif == null) begin
       `uvm_warning("HOST_AGENT", "No wishbone_master_if in config (Backdoor write disabled)")
    end

    // 3. CREATE SUB-COMPONENTS
    m_monitor = host_monitor::type_id::create("m_monitor", this);

    if (get_is_active() == UVM_ACTIVE) begin
      m_driver    = host_driver::type_id::create("m_driver", this);
      m_sequencer = host_sequencer::type_id::create("m_sequencer", this);
    end
  endfunction : build_phase

  // -----------------------------------------------------------------------
  // CONNECT PHASE
  // -----------------------------------------------------------------------
  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    
    // Connect Monitor (Standard)
    // m_monitor.item_collected_port.connect(...) // Handled in Env

    if (get_is_active() == UVM_ACTIVE) begin
      // 1. Connect Driver to Sequencer
      m_driver.seq_item_port.connect(m_sequencer.seq_item_export);

      // 2. PASS MEMORY INTERFACE TO SEQUENCER (The Fix)
      //    We do this here because both m_sequencer and m_config exist now.
      if (m_config.mem_vif != null) begin
         m_sequencer.mem_vif = m_config.mem_vif; 
      end
    end
    
  endfunction : connect_phase

endclass