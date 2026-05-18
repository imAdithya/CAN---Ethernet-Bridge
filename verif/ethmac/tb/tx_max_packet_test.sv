// tb/tests/tx_max_packet_test.sv
`include "uvm_macros.svh"
import uvm_pkg::*;

class tx_max_packet_test extends base_test;
  `uvm_component_utils(tx_max_packet_test)

  function new(string name = "tx_max_packet_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    tx_max_packet_seq seq;
    
    phase.raise_objection(this);
    `uvm_info(get_type_name(), "Starting TX-02: Max Packet Test...", UVM_MEDIUM)

    // 1. Reset DUT
    m_host_cfg.vif.rst = 1;
    #200ns;
    m_host_cfg.vif.rst = 0;
    #1000ns; // Wait for initialization

    // 2. Start Max Packet Sequence
    seq = tx_max_packet_seq::type_id::create("seq");
    seq.start(m_env.m_host_agent.m_sequencer);

    // 3. Allow time for trailing activity
    #5000ns;
    
    `uvm_info(get_type_name(), "TX-02 Test Finished.", UVM_MEDIUM)
    phase.drop_objection(this);
  endtask

endclass