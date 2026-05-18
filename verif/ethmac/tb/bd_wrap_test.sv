// bd_wrap_test.sv - SYS-06: BD Wrap Test
class bd_wrap_test extends base_test;
  `uvm_component_utils(bd_wrap_test)

  function new(string name = "bd_wrap_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    uvm_config_db#(bit)::set(this, "m_env.m_scoreboard", "disable_rx_check", 1);
  endfunction

  virtual task run_phase(uvm_phase phase);
    bd_wrap_seq seq;

    phase.raise_objection(this);
    `uvm_info(get_type_name(), "Starting BD Wrap Test (SYS-06)...", UVM_LOW)

    m_host_cfg.vif.rst = 1;
    #200ns;
    m_host_cfg.vif.rst = 0;
    #200ns;

    seq = bd_wrap_seq::type_id::create("seq");
    seq.start(m_env.m_host_agent.m_sequencer);

    #5000ns;
    `uvm_info(get_type_name(), "BD Wrap Test (SYS-06) Finished.", UVM_LOW)
    phase.drop_objection(this);
  endtask

endclass
