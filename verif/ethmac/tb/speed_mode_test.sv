// speed_mode_test.sv - SYS-03: Speed Mode Test
class speed_mode_test extends base_test;
  `uvm_component_utils(speed_mode_test)

  function new(string name = "speed_mode_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    // Disable scoreboard — multi-phase test with clock changes
    uvm_config_db#(bit)::set(this, "m_env.m_scoreboard", "disable_rx_check", 1);
  endfunction

  virtual task run_phase(uvm_phase phase);
    speed_mode_seq seq;

    phase.raise_objection(this);
    `uvm_info(get_type_name(), "Starting Speed Mode Test (SYS-03)...", UVM_LOW)

    m_host_cfg.vif.rst = 1;
    #200ns;
    m_host_cfg.vif.rst = 0;
    #200ns;

    seq = speed_mode_seq::type_id::create("seq");
    seq.start(m_env.m_host_agent.m_sequencer);

    #5000ns;
    `uvm_info(get_type_name(), "Speed Mode Test (SYS-03) Finished.", UVM_LOW)
    phase.drop_objection(this);
  endtask

endclass
