// tb/tests/reg_write_test.sv
`include "uvm_macros.svh"
import uvm_pkg::*;

class reg_write_test extends base_test;
  `uvm_component_utils(reg_write_test)

  function new(string name = "reg_write_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    reg_write_seq seq;
    phase.raise_objection(this);

    `uvm_info(get_type_name(), "Starting register write test...", UVM_MEDIUM)
    
    // Create and start the sequence
    seq = reg_write_seq::type_id::create("seq");
    seq.start(m_env.m_host_agent.m_sequencer);
    
    // Configure the sequence with a specific address and data
    seq.addr = `ETH_MAC_ADDR0_ADR;
    seq.data = 32'hAABBCCDD;

    #200ns;
    
    `uvm_info(get_type_name(), "Register write test finished.", UVM_MEDIUM)
    phase.drop_objection(this);
  endtask : run_phase

endclass : reg_write_test