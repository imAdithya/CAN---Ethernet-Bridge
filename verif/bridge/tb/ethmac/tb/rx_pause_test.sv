// rx_pause_test.sv - FD-02: RX PAUSE Frame Test
class rx_pause_test extends base_test;
  `uvm_component_utils(rx_pause_test)

  function new(string name = "rx_pause_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    rx_pause_seq seq;

    phase.raise_objection(this);
    `uvm_info(get_type_name(), "Starting RX PAUSE Frame Test (FD-02)...", UVM_LOW)

    // 1. Reset DUT
    m_host_cfg.vif.rst = 1;
    #200ns;
    m_host_cfg.vif.rst = 0;
    #200ns;

    // 2. Run Sequence
    seq = rx_pause_seq::type_id::create("seq");
    seq.start(m_env.m_host_agent.m_sequencer);

    // 3. Wait for trailing activity
    #5000ns;

    `uvm_info(get_type_name(), "RX PAUSE Frame Test (FD-02) Finished.", UVM_LOW)
    phase.drop_objection(this);
  endtask

endclass
