// tb/tests/base_test.sv
`include "uvm_macros.svh"
import uvm_pkg::*;

class base_test extends uvm_test;
  `uvm_component_utils(base_test)

  // Environment and Config Objects
  env m_env;
  host_agent_config m_host_cfg;
  phy_agent_config  m_phy_cfg;
  dma_agent_config  m_dma_cfg; // <--- NEW: DMA Config Object

  function new(string name = "base_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    
    // 1. Create Configuration Objects
    m_host_cfg = host_agent_config::type_id::create("m_host_cfg");
    m_phy_cfg  = phy_agent_config ::type_id::create("m_phy_cfg");
    m_dma_cfg  = dma_agent_config ::type_id::create("m_dma_cfg"); // <--- Create it

    // Enable all agents
    m_host_cfg.is_active = UVM_ACTIVE;
    m_phy_cfg.is_active  = UVM_ACTIVE;
    m_dma_cfg.is_active = UVM_ACTIVE;

    // 2. Retrieve Interfaces from uvm_config_db
    //    (These must be set in tb_top.sv using these specific field names)

    // A. Host Interface (Slave connection to DUT)
    if (!uvm_config_db#(virtual wishbone_slave_if)::get(this, "", "vif_slave", m_host_cfg.vif)) begin
      // Fallback: try "vif" if "vif_slave" fails (common naming mismatch)
      if (!uvm_config_db#(virtual wishbone_slave_if)::get(this, "", "vif", m_host_cfg.vif))
        `uvm_fatal("VIF_GET", "Cannot get virtual interface for host_agent (vif_slave)")
    end
      
    // B. PHY Interface (MII connection to DUT)
    if (!uvm_config_db#(virtual mii_if)::get(this, "", "vif_mii", m_phy_cfg.vif)) begin
       if (!uvm_config_db#(virtual mii_if)::get(this, "", "mii_vif", m_phy_cfg.vif))
        `uvm_fatal("VIF_GET", "Cannot get virtual interface for phy_agent (vif_mii)")
    end

    // C. DMA/Memory Interface (Master connection from DUT)
    //    This is crucial for the DMA Agent AND the Backdoor Memory Write
    if (!uvm_config_db#(virtual wishbone_master_if)::get(this, "", "mem_vif", m_dma_cfg.vif)) begin
       `uvm_fatal("VIF_GET", "Cannot get virtual interface for dma_agent (mem_vif). Ensure tb_top sets 'mem_vif'.")
    end

    // Link the Memory Interface to Host Config as well (for Backdoor writes)
    m_host_cfg.mem_vif = m_dma_cfg.vif;

    // 3. Publish Configurations to the DB
    //    The wildcards (*) ensure the agents and their children (drivers/monitors) can see them.
    uvm_config_db#(host_agent_config)::set(this, "m_env.m_host_agent*", "config", m_host_cfg);
    uvm_config_db#(phy_agent_config) ::set(this, "m_env.m_phy_agent*",  "config", m_phy_cfg);
    
    // Forward MII interface to scoreboard for MDIO bus monitoring
    uvm_config_db#(virtual mii_if)::set(this, "m_env.m_scoreboard", "vif_mii", m_phy_cfg.vif);
    
    // <--- THIS WAS MISSING: Publish DMA Config
    uvm_config_db#(dma_agent_config) ::set(this, "m_env.m_dma_agent*",  "config", m_dma_cfg);

    // 4. Create the Environment
    m_env = env::type_id::create("m_env", this);
    
  endfunction : build_phase

  virtual task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    `uvm_info("BASE_TEST", "Base test run phase starting...", UVM_MEDIUM)
    #100ns;
    phase.drop_objection(this);
  endtask

  virtual function void end_of_elaboration_phase(uvm_phase phase);
    uvm_top.print_topology();
  endfunction

endclass