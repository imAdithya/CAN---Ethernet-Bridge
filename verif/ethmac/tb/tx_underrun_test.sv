// tx_underrun_test.sv - ERR-01: TX Underrun Test
class tx_underrun_test extends base_test;
  `uvm_component_utils(tx_underrun_test)

  function new(string name = "tx_underrun_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    tx_underrun_seq seq;

    phase.raise_objection(this);
    `uvm_info(get_type_name(), "Starting TX Underrun Test (ERR-01)...", UVM_LOW)

    m_host_cfg.vif.rst = 1;
    #200ns;
    m_host_cfg.vif.rst = 0;
    #200ns;

    seq = tx_underrun_seq::type_id::create("seq");
    seq.start(m_env.m_host_agent.m_sequencer);

    #5000ns;
    `uvm_info(get_type_name(), "TX Underrun Test (ERR-01) Finished.", UVM_LOW)
    phase.drop_objection(this);
  endtask

endclass
