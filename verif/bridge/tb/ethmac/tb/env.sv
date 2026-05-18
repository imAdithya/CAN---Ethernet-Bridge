// tb/uvm_components/env/env.sv
class env extends uvm_env;
  `uvm_component_utils(env)

  host_agent m_host_agent;
  dma_agent  m_dma_agent;
  phy_agent  m_phy_agent;
  scoreboard m_scoreboard;  

  // Coverage component
  eth_coverage m_coverage;

  function new(string name = "env", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    virtual mii_if mii_vif;
    super.build_phase(phase);
    
    m_host_agent = host_agent::type_id::create("m_host_agent", this);
    m_phy_agent  = phy_agent::type_id::create("m_phy_agent", this);
    m_dma_agent  = dma_agent ::type_id::create("m_dma_agent",  this);
    m_scoreboard = scoreboard::type_id::create("m_scoreboard", this);
    
    // Forward MII interface to scoreboard for MDIO bus monitoring
    if (uvm_config_db#(virtual mii_if)::get(this, "", "vif_mii", mii_vif))
      uvm_config_db#(virtual mii_if)::set(this, "m_scoreboard", "vif_mii", mii_vif);
    
    // Create the coverage component
    m_coverage   = eth_coverage::type_id::create("m_coverage", this);
    
  endfunction : build_phase

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    
    // Connect monitor to scoreboard and coverage
    m_host_agent.m_monitor.item_collected_port.connect(m_scoreboard.host_export);
    m_dma_agent.m_monitor.item_collected_port.connect(m_scoreboard.dma_export);
    m_host_agent.m_monitor.item_collected_port.connect(m_coverage.analysis_export);

    m_phy_agent.m_monitor.item_collected_port.connect(m_scoreboard.phy_export);
      m_host_agent.m_sequencer.phy_rx_event =
      m_phy_agent.m_config.rx_frame_started;

  endfunction : connect_phase

endclass : env