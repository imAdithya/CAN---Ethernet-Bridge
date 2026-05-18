// rx_short_test.sv - ERR-06: RX Short Frame Test
class rx_short_test extends base_test;
  `uvm_component_utils(rx_short_test)

  function new(string name = "rx_short_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    uvm_config_db#(bit)::set(this, "m_env.m_scoreboard", "disable_rx_check", 1);
  endfunction

  virtual task run_phase(uvm_phase phase);
    rx_short_seq seq;

    phase.raise_objection(this);
    `uvm_info(get_type_name(), "Starting RX Short Frame Test (ERR-06)...", UVM_LOW)

    m_host_cfg.vif.rst = 1;
    #200ns;
    m_host_cfg.vif.rst = 0;
    #200ns;

    seq = rx_short_seq::type_id::create("seq");
    seq.start(m_env.m_host_agent.m_sequencer);

    #5000ns;
    `uvm_info(get_type_name(), "RX Short Frame Test (ERR-06) Finished.", UVM_LOW)
    phase.drop_objection(this);
  endtask

endclass
