`include "uvm_macros.svh"
import uvm_pkg::*;

class tx_huge_packet_test extends base_test;
  `uvm_component_utils(tx_huge_packet_test)

  function new(string name = "tx_huge_packet_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    tx_huge_packet_seq seq;
    
    phase.raise_objection(this);
    `uvm_info(get_type_name(), "Starting TX-05: Huge Packet (Half Duplex)...", UVM_MEDIUM)

    // 1. Force Idle Medium (CRITICAL for Half Duplex Stability)
    //m_phy_cfg.vif.force_idle();

    // 2. Reset DUT
    m_host_cfg.vif.rst = 1;
    #200ns;
    m_host_cfg.vif.rst = 0;
    #1000ns; 

    // 3. Start Sequence
    seq = tx_huge_packet_seq::type_id::create("seq");
    seq.start(m_env.m_host_agent.m_sequencer);

    // 4. Wait for completion (Longer wait for huge packet)
    #5000ns;

    // Release forces
    //m_phy_cfg.vif.release_idle();
    
    `uvm_info(get_type_name(), "TX-05 Test Finished.", UVM_MEDIUM)
    phase.drop_objection(this);
  endtask
endclass