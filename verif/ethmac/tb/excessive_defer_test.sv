// excessive_defer_test.sv - HD-04: Excessive Deferral Abort
class excessive_defer_test extends base_test;
  `uvm_component_utils(excessive_defer_test)

  function new(string name = "excessive_defer_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    excessive_defer_seq seq;
    phase.raise_objection(this);

    `uvm_info(get_type_name(), "Starting Excessive Deferral Test (HD-04)...", UVM_LOW)

    wait (m_host_cfg.vif.rst === 1'b0);
    #1000ns;

    seq = excessive_defer_seq::type_id::create("seq");
    seq.start(m_env.m_host_agent.m_sequencer);

    #5000ns;
    `uvm_info(get_type_name(), "Excessive Deferral Test finished.", UVM_LOW)
    phase.drop_objection(this);
  endtask : run_phase

endclass : excessive_defer_test
