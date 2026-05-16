// can_wb_agent.sv — CAN Wishbone Agent wrapper
class can_wb_agent extends uvm_agent;
  `uvm_component_utils(can_wb_agent)

  can_wb_agent_config m_config;
  can_wb_driver       m_driver;
  can_wb_monitor      m_monitor;

  function new(string name = "can_wb_agent", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(can_wb_agent_config)::get(this, "", "config", m_config))
      `uvm_fatal("CFG", "Cannot get can_wb_agent_config")

    m_monitor = can_wb_monitor::type_id::create("m_monitor", this);
    if (m_config.is_active == UVM_ACTIVE)
      m_driver = can_wb_driver::type_id::create("m_driver", this);
  endfunction
endclass
