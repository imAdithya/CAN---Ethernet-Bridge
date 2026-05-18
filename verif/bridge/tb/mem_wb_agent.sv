// mem_wb_agent.sv — Memory Wishbone Agent wrapper
class mem_wb_agent extends uvm_agent;
  `uvm_component_utils(mem_wb_agent)

  mem_wb_agent_config m_config;
  mem_wb_driver       m_driver;
  mem_wb_monitor      m_monitor;

  function new(string name = "mem_wb_agent", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(mem_wb_agent_config)::get(this, "", "config", m_config))
      `uvm_fatal("CFG", "Cannot get mem_wb_agent_config")

    m_monitor = mem_wb_monitor::type_id::create("m_monitor", this);
    if (m_config.is_active == UVM_ACTIVE)
      m_driver = mem_wb_driver::type_id::create("m_driver", this);
  endfunction
endclass
