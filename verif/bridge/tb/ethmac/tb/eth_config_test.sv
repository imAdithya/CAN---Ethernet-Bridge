// tb/tests/eth_config_test.sv
class eth_config_test extends base_test;
  `uvm_component_utils(eth_config_test)

  function new(string name = "eth_config_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    eth_config_seq seq;
    phase.raise_objection(this);

    `uvm_info(get_type_name(), "Starting full MAC configuration test...", UVM_MEDIUM)
    
    // Create and start the sequence
    seq = eth_config_seq::type_id::create("seq");
    
    // Optional: You can constrain the configuration values from the test
    // For example, to set a different MAC address:
    // assert(seq.randomize() with { mac_addr == 48'hDE_AD_BE_EF_CA_FE; });
    
    seq.start(m_env.m_host_agent.m_sequencer);

    #200ns;
    
    `uvm_info(get_type_name(), "Full MAC configuration test finished.", UVM_MEDIUM)
    phase.drop_objection(this);
  endtask : run_phase

endclass : eth_config_test