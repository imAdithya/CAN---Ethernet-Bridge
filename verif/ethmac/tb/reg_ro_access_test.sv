`include "uvm_macros.svh"
import uvm_pkg::*;

class reg_ro_access_test extends base_test;
  `uvm_component_utils(reg_ro_access_test)

  function new(string name = "reg_ro_access_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    reg_ro_access_seq seq;
    phase.raise_objection(this);

    `uvm_info(get_type_name(), "Starting Read-Only register test...", UVM_MEDIUM)

    // 1. Apply Reset
    `uvm_info(get_type_name(), "Applying reset to the DUT...", UVM_MEDIUM)
    m_host_cfg.vif.rst = 1;
    #100ns;
    m_host_cfg.vif.rst = 0;
    `uvm_info(get_type_name(), "Reset released.", UVM_MEDIUM)
    #50ns; // Let reset settle
    
    // 2. Create, randomize, and start the sequence
    seq = reg_ro_access_seq::type_id::create("seq");
    void'(seq.randomize());
    seq.start(m_env.m_host_agent.m_sequencer);

    // 3. Wait for sequence to finish
    #2000ns;

    `uvm_info(get_type_name(), "Read-Only register test finished.", UVM_MEDIUM)
    phase.drop_objection(this);
  endtask : run_phase

endclass : reg_ro_access_test