// tb/tests/reg_access_random_test.sv
`include "uvm_macros.svh"
import uvm_pkg::*;

class reg_access_random_test extends base_test;
  `uvm_component_utils(reg_access_random_test)

  function new(string name = "reg_access_random_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    random_reg_access_seq seq;
    phase.raise_objection(this);

    `uvm_info(get_type_name(), "Starting random register access test...", UVM_MEDIUM)

    // 1. Apply Reset (same as base_test)
    `uvm_info(get_type_name(), "Applying reset to the DUT...", UVM_MEDIUM)
    m_host_cfg.vif.rst = 1;
    #100ns;
    m_host_cfg.vif.rst = 0;
    `uvm_info(get_type_name(), "Reset released.", UVM_MEDIUM)
    
    // 2. Create the sequence
    seq = random_reg_access_seq::type_id::create("seq");
    
    // 3. Randomize the test itself
    // We are randomizing the 'num_transactions' variable inside the sequence.
    // If we wanted 50 specific transactions: assert(seq.randomize() with { num_transactions == 50; });
    // By not adding a constraint, it will use the default (20-100).
    assert(seq.randomize());

    // 4. Start the sequence
    seq.start(m_env.m_host_agent.m_sequencer);

    // 5. Wait for the sequence to complete and add a small delay to finish
    #1000ns;

    `uvm_info(get_type_name(), "Random register access test finished.", UVM_MEDIUM)
    phase.drop_objection(this);
  endtask : run_phase

endclass : reg_access_random_test

