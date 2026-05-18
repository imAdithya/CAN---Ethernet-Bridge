// tb/tests/tx_random_test.sv
`include "uvm_macros.svh"
import uvm_pkg::*;

class tx_random_test extends base_test;
  `uvm_component_utils(tx_random_test)

  function new(string name = "tx_random_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    tx_random_seq seq;
    
    phase.raise_objection(this);
    `uvm_info(get_type_name(), "Starting TX-04: Half Duplex Random Test...", UVM_MEDIUM)

    // ----------------------------------------------------------
    // 1. Force Idle Medium (CRITICAL FOR HALF DUPLEX TX TESTS)
    // ----------------------------------------------------------
    // This allows the MAC to transmit randomized packets without 
    // getting stuck in "Deferral" state due to phantom carrier sense.
    //force m_phy_cfg.vif.col = 1'b0;
    //force m_phy_cfg.vif.crs = 1'b0;

    // 2. Reset DUT
    m_host_cfg.vif.rst = 1;
    #200ns;
    m_host_cfg.vif.rst = 0;
    #1000ns; 

    // 3. Start Sequence
    seq = tx_random_seq::type_id::create("seq");
    seq.start(m_env.m_host_agent.m_sequencer);

    // 4. Cleanup
    #2000ns;
    
    // Release forces before ending (clean exit)
    //release m_phy_cfg.vif.col;
    //release m_phy_cfg.vif.crs;
    
    `uvm_info(get_type_name(), "TX-04 Test Finished.", UVM_MEDIUM)
    phase.drop_objection(this);
  endtask
endclass