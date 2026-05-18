`include "uvm_macros.svh"
import uvm_pkg::*;

class tx_broad_multi_test extends base_test;
  `uvm_component_utils(tx_broad_multi_test)

  function new(string name = "tx_broad_multi_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    tx_broad_multi_seq seq;
    
    phase.raise_objection(this);
    `uvm_info(get_type_name(), "Starting TX-06: Broadcast/Multicast (Half Duplex)...", UVM_MEDIUM)

    // 1. Force Idle (Essential for Half Duplex)
    //m_phy_cfg.vif.force_idle();

    // 2. Reset
    m_host_cfg.vif.rst = 1;
    #200ns;
    m_host_cfg.vif.rst = 0;
    #1000ns; 

    // 3. Run Sequence
    seq = tx_broad_multi_seq::type_id::create("seq");
    seq.start(m_env.m_host_agent.m_sequencer);

    // 4. Wait & Clean up
    #2000ns;
    //m_phy_cfg.vif.release_idle();
    
    `uvm_info(get_type_name(), "TX-06 Test Finished.", UVM_MEDIUM)
    phase.drop_objection(this);
  endtask
endclass