`include "uvm_macros.svh"
import uvm_pkg::*;

class tx_full_ring_test extends base_test;
  `uvm_component_utils(tx_full_ring_test)

  function new(string name = "tx_full_ring_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    tx_full_ring_seq seq;
    
    phase.raise_objection(this);
    `uvm_info(get_type_name(), "Starting TX-03: Full Ring Back-to-Back Test...", UVM_MEDIUM)

    // 1. Force Idle Medium (Critical for Back-to-Back stability)
    //force m_phy_cfg.vif.col = 1'b0;
    //force m_phy_cfg.vif.crs = 1'b0;

    // 2. Reset DUT
    m_host_cfg.vif.rst = 1;
    #200ns;
    m_host_cfg.vif.rst = 0;
    #1000ns; 

    // 3. Start Sequence
    seq = tx_full_ring_seq::type_id::create("seq");
    seq.start(m_env.m_host_agent.m_sequencer);

    // 4. Wait for potential trailing activity
    #2000ns;

    // Release forces
    //release m_phy_cfg.vif.col;
    //release m_phy_cfg.vif.crs;
    
    `uvm_info(get_type_name(), "TX-03 Test Finished.", UVM_MEDIUM)
    phase.drop_objection(this);
  endtask
endclass