// backoff_test.sv - HD-05: Random Backoff After Collision
class backoff_test extends base_test;
  `uvm_component_utils(backoff_test)

  function new(string name = "backoff_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    backoff_seq seq;
    phase.raise_objection(this);

    `uvm_info(get_type_name(), "Starting Backoff Test (HD-05)...", UVM_LOW)

    // Wait for reset deassert
    wait (m_host_cfg.vif.rst === 1'b0);
    #1000ns;

    // Run the backoff sequence
    seq = backoff_seq::type_id::create("seq");
    seq.start(m_env.m_host_agent.m_sequencer);

    #5000ns;
    `uvm_info(get_type_name(), "Backoff Test finished.", UVM_LOW)
    phase.drop_objection(this);
  endtask : run_phase

endclass : backoff_test
