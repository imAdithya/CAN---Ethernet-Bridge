`include "uvm_macros.svh"
import uvm_pkg::*;

class reg_burst_test extends base_test;
  `uvm_component_utils(reg_burst_test)

  function new(string name = "reg_burst_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    reg_burst_seq seq;
    phase.raise_objection(this);

    `uvm_info(get_type_name(), "Starting register burst test...", UVM_MEDIUM)

    // 1. Apply Reset
    `uvm_info(get_type_name(), "Applying reset to the DUT...", UVM_MEDIUM)
    m_host_cfg.vif.rst = 1;
    #100ns;
    m_host_cfg.vif.rst = 0;
    `uvm_info(get_type_name(), "Reset released.", UVM_MEDIUM)
    #50ns; // Let reset settle
    
    // 2. Create, randomize, and start the sequence
    seq = reg_burst_seq::type_id::create("seq");
    void'(seq.randomize()); // Randomizes num_write_transactions
    seq.start(m_env.m_host_agent.m_sequencer);

    // 3. Wait for sequence to finish
    #3000ns; // Give it time to run many transactions

    `uvm_info(get_type_name(), "Register burst test finished.", UVM_MEDIUM)
    phase.drop_objection(this);
  endtask : run_phase

endclass : reg_burst_test