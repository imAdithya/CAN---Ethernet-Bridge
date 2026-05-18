// tb/tests/reg_read_test.sv
`include "uvm_macros.svh"
import uvm_pkg::*;

class reg_read_test extends base_test;
  `uvm_component_utils(reg_read_test)

  function new(string name = "reg_read_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    reg_write_seq write_seq;
    reg_read_seq read_seq;
    phase.raise_objection(this);

    `uvm_info(get_type_name(), "Starting register read test...", UVM_MEDIUM)

    // 1. First, write a known value to a register
    write_seq = reg_write_seq::type_id::create("write_seq");
    write_seq.addr = `ETH_IPGT_ADR;
    write_seq.data = 32'h0000001A;
    write_seq.start(m_env.m_host_agent.m_sequencer);

    #100ns;

    // 2. Now, create and start the read sequence to read it back
    read_seq = reg_read_seq::type_id::create("read_seq");
    read_seq.addr = `ETH_IPGT_ADR;
    read_seq.start(m_env.m_host_agent.m_sequencer);

    // 3. NO CHECKING HERE. The scoreboard will report any errors.

    #100ns;
    
    `uvm_info(get_type_name(), "Register read test finished.", UVM_MEDIUM)
    phase.drop_objection(this);
  endtask : run_phase

endclass : reg_read_test