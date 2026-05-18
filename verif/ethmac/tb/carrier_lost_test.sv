// carrier_lost_test.sv - HD-06: Carrier Sense Lost
class carrier_lost_test extends base_test;
  `uvm_component_utils(carrier_lost_test)

  function new(string name = "carrier_lost_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    carrier_lost_seq seq;
    phase.raise_objection(this);

    `uvm_info(get_type_name(), "Starting Carrier Sense Lost Test (HD-06)...", UVM_LOW)

    wait (m_host_cfg.vif.rst === 1'b0);
    #1000ns;

    seq = carrier_lost_seq::type_id::create("seq");
    seq.start(m_env.m_host_agent.m_sequencer);

    #5000ns;
    `uvm_info(get_type_name(), "Carrier Sense Lost Test finished.", UVM_LOW)
    phase.drop_objection(this);
  endtask : run_phase

endclass : carrier_lost_test
