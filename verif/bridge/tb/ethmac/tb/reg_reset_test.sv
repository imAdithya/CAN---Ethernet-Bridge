`include "uvm_macros.svh"
import uvm_pkg::*;

class reg_reset_test extends base_test;
  `uvm_component_utils(reg_reset_test)

  function new(string name = "reg_reset_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    reg_reset_seq seq;
    phase.raise_objection(this);

    `uvm_info(get_type_name(), "Starting register reset test...", UVM_MEDIUM)

    // 1. Apply Reset (this is the action we are verifying)
    `uvm_info(get_type_name(), "Applying reset to the DUT...", UVM_MEDIUM)
    m_host_cfg.vif.rst = 1;
    #100ns;
    m_host_cfg.vif.rst = 0;
    `uvm_info(get_type_name(), "Reset released.", UVM_MEDIUM)
    
    // 2. Wait a few cycles for reset logic to settle
    #50ns;

    // 3. Create and start the reset check sequence
    seq = reg_reset_seq::type_id::create("seq");
    seq.start(m_env.m_host_agent.m_sequencer);

    // 4. Wait for the sequence to complete
    #1000ns;

    `uvm_info(get_type_name(), "Register reset test finished.", UVM_MEDIUM)
    phase.drop_objection(this);
  endtask : run_phase

endclass : reg_reset_test