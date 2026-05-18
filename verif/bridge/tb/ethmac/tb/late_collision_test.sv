// late_collision_test.sv - HD-03: Late Collision Abort
class late_collision_test extends base_test;
  `uvm_component_utils(late_collision_test)

  function new(string name = "late_collision_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    late_collision_seq seq;
    phase.raise_objection(this);

    `uvm_info(get_type_name(), "Starting Late Collision Test (HD-03)...", UVM_LOW)

    wait (m_host_cfg.vif.rst === 1'b0);
    #1000ns;

    seq = late_collision_seq::type_id::create("seq");
    seq.start(m_env.m_host_agent.m_sequencer);

    #5000ns;
    `uvm_info(get_type_name(), "Late Collision Test finished.", UVM_LOW)
    phase.drop_objection(this);
  endtask : run_phase

endclass : late_collision_test
