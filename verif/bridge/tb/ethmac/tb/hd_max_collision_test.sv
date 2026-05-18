// hd_max_collision_test.sv - HD-02: Max Collision (Retry Limit)
class hd_max_collision_test extends base_test;
  `uvm_component_utils(hd_max_collision_test)

  function new(string name = "hd_max_collision_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    hd_max_collision_seq seq;
    phase.raise_objection(this);

    `uvm_info(get_type_name(), "Starting HD Max Collision Test (HD-02)...", UVM_LOW)

    wait (m_host_cfg.vif.rst === 1'b0);
    #1000ns;

    seq = hd_max_collision_seq::type_id::create("seq");
    seq.start(m_env.m_host_agent.m_sequencer);

    #5000ns;
    `uvm_info(get_type_name(), "HD Max Collision Test finished.", UVM_LOW)
    phase.drop_objection(this);
  endtask
endclass