// bridge_base_test.sv — Base test for bridge UVM testbench


class bridge_base_test extends uvm_test;
  `uvm_component_utils(bridge_base_test)

  bridge_env          m_env;
  host_agent_config   m_host_cfg;
  can_wb_agent_config m_can_cfg;
  mem_wb_agent_config m_mem_cfg;

  function new(string name = "bridge_base_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    // Create config objects
    m_host_cfg = host_agent_config::type_id::create("m_host_cfg");
    m_can_cfg  = can_wb_agent_config::type_id::create("m_can_cfg");
    m_mem_cfg  = mem_wb_agent_config::type_id::create("m_mem_cfg");

    // Set all agents active
    m_host_cfg.is_active = UVM_ACTIVE;
    m_can_cfg.is_active  = UVM_ACTIVE;
    m_mem_cfg.is_active  = UVM_ACTIVE;

    // Retrieve interfaces from config_db (set in tb_bridge_top.sv)
    if (!uvm_config_db#(virtual wishbone_slave_if)::get(this, "", "vif_host", m_host_cfg.vif))
      `uvm_fatal("VIF", "Cannot get host WB interface")
      
    if (!uvm_config_db#(virtual wishbone_master_if)::get(this, "", "vif_host_mem", m_host_cfg.mem_vif))
      `uvm_fatal("VIF", "Cannot get host MEM interface")

    if (!uvm_config_db#(virtual can_wb_if)::get(this, "", "vif_can", m_can_cfg.vif))
      `uvm_fatal("VIF", "Cannot get CAN WB interface")

    if (!uvm_config_db#(virtual mem_wb_if)::get(this, "", "vif_mem", m_mem_cfg.vif))
      `uvm_fatal("VIF", "Cannot get MEM WB interface")

    // Publish configs to agents
    uvm_config_db#(host_agent_config)::set(this, "m_env.m_host_agent*", "config", m_host_cfg);
    uvm_config_db#(can_wb_agent_config)::set(this, "m_env.m_can_agent*", "config", m_can_cfg);
    uvm_config_db#(mem_wb_agent_config)::set(this, "m_env.m_mem_agent*", "config", m_mem_cfg);

    // Create environment
    m_env = bridge_env::type_id::create("m_env", this);
  endfunction

  virtual task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    `uvm_info("BASE_TEST", "Bridge base test starting...", UVM_MEDIUM)
    #100ns;
    phase.drop_objection(this);
  endtask

  virtual function void end_of_elaboration_phase(uvm_phase phase);
    uvm_top.print_topology();
  endfunction
endclass
