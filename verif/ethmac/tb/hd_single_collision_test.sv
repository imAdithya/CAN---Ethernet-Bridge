// hd_single_collision_test.sv - HD-01: Single Collision + Retransmission
class hd_single_collision_test extends base_test;
  `uvm_component_utils(hd_single_collision_test)

  function new(string name = "hd_single_collision_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    tx_single_collision_seq seq;
    phase.raise_objection(this);

    `uvm_info(get_type_name(), "Starting HD Single Collision Test (HD-01)...", UVM_LOW)

    // Wait for reset deassert (handled by base_test)
    wait (m_host_cfg.vif.rst === 1'b0);
    #1000ns;

    // Run the collision sequence
    seq = tx_single_collision_seq::type_id::create("seq");
    seq.start(m_env.m_host_agent.m_sequencer);

    #5000ns;
    `uvm_info(get_type_name(), "HD Single Collision Test finished.", UVM_LOW)
    phase.drop_objection(this);
  endtask : run_phase

endclass : hd_single_collision_test