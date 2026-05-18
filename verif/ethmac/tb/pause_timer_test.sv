// pause_timer_test.sv - FD-03: PAUSE Timer Test
class pause_timer_test extends base_test;
  `uvm_component_utils(pause_timer_test)

  function new(string name = "pause_timer_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    pause_timer_seq seq;

    phase.raise_objection(this);
    `uvm_info(get_type_name(), "Starting PAUSE Timer Test (FD-03)...", UVM_LOW)

    m_host_cfg.vif.rst = 1;
    #200ns;
    m_host_cfg.vif.rst = 0;
    #200ns;

    seq = pause_timer_seq::type_id::create("seq");
    seq.start(m_env.m_host_agent.m_sequencer);

    #5000ns;
    `uvm_info(get_type_name(), "PAUSE Timer Test (FD-03) Finished.", UVM_LOW)
    phase.drop_objection(this);
  endtask

endclass
