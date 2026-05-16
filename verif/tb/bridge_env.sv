// bridge_env.sv — UVM Environment for CAN-Ethernet Bridge

class bridge_env extends uvm_env;
  `uvm_component_utils(bridge_env)

  // Agents
  host_agent       m_host_agent;    // Reused from ETH MAC TB
  can_wb_agent     m_can_agent;     // NEW: CAN controller model
  mem_wb_agent     m_mem_agent;     // NEW: RAM + ETH MAC BD model

  // Scoreboard and coverage
  bridge_scoreboard m_scoreboard;
  bridge_coverage   m_coverage;

  function new(string name = "bridge_env", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    m_host_agent  = host_agent::type_id::create("m_host_agent", this);
    m_can_agent   = can_wb_agent::type_id::create("m_can_agent", this);
    m_mem_agent   = mem_wb_agent::type_id::create("m_mem_agent", this);
    m_scoreboard  = bridge_scoreboard::type_id::create("m_scoreboard", this);
    m_coverage    = bridge_coverage::type_id::create("m_coverage", this);

    // Publish coverage handle so tb_bridge_top can sample FSM states
    uvm_config_db#(bridge_coverage)::set(null, "uvm_test_top.m_env", "m_coverage_handle", m_coverage);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);

    // Host monitor → scoreboard + coverage
    m_host_agent.m_monitor.item_collected_port.connect(m_scoreboard.host_export);
    m_host_agent.m_monitor.item_collected_port.connect(m_coverage.analysis_export);

    // CAN monitor → scoreboard (CAN frame reconstruction)
    m_can_agent.m_monitor.can_frame_port.connect(m_scoreboard.can_export);

    // Memory monitor → scoreboard (frame data tracking)
    m_mem_agent.m_monitor.item_collected_port.connect(m_scoreboard.mem_export);
  endfunction
endclass
