// rx_bad_crc_test.sv - ERR-03: RX Bad CRC Test
class rx_bad_crc_test extends base_test;
  `uvm_component_utils(rx_bad_crc_test)

  function new(string name = "rx_bad_crc_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction


  virtual task run_phase(uvm_phase phase);
    rx_bad_crc_seq seq;

    phase.raise_objection(this);
    `uvm_info(get_type_name(), "Starting RX Bad CRC Test (ERR-03)...", UVM_LOW)

    m_host_cfg.vif.rst = 1;
    #200ns;
    m_host_cfg.vif.rst = 0;
    #200ns;

    seq = rx_bad_crc_seq::type_id::create("seq");
    seq.start(m_env.m_host_agent.m_sequencer);

    #5000ns;
    `uvm_info(get_type_name(), "RX Bad CRC Test (ERR-03) Finished.", UVM_LOW)
    phase.drop_objection(this);
  endtask

endclass
