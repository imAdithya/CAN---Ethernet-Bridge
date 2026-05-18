// b2b_rx_test.sv - Test for receiving back-to-back packets
class b2b_rx_test extends base_test;
  `uvm_component_utils(b2b_rx_test)

  function new(string name="b2b_rx_test", uvm_component parent=null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    b2b_rx_seq          host_seq;
    phy_b2b_packet_seq  phy_seq;

    phase.raise_objection(this);

    `uvm_info(get_type_name(), "Starting B2B-RX: Back-to-Back Packet Reception", UVM_MEDIUM)

    // Wait for Reset
    `uvm_info(get_type_name(), "Waiting for Reset...", UVM_MEDIUM)
    wait (m_host_cfg.vif.rst === 1'b0);
    `uvm_info(get_type_name(), "Reset Released. Starting Test...", UVM_MEDIUM)
    
    // Initial stabilization
    #1000ns;

    host_seq = b2b_rx_seq         ::type_id::create("host_seq");
    phy_seq  = phy_b2b_packet_seq ::type_id::create("phy_seq");

    // Randomize number of packets
    if (!phy_seq.randomize()) begin
      `uvm_fatal(get_type_name(), "Failed to randomize phy_b2b_packet_seq")
    end

    `uvm_info(get_type_name(), $sformatf("Sending %0d back-to-back packets", phy_seq.num_packets), UVM_MEDIUM)

    fork
      begin
        // Delay to ensure host configuration completes before packet transmission
        #10000ns; 
        `uvm_info("TEST", "Triggering PHY Sequence (B2B Packets)...", UVM_MEDIUM)
        phy_seq.start(m_env.m_phy_agent.m_sequencer); 
      end
      
      begin
        // Host Sequence: Configures -> Waits -> Polls
        host_seq.start(m_env.m_host_agent.m_sequencer); 
      end
    join 

    // Drain time for Scoreboard
    #2000ns; 

    `uvm_info(get_type_name(), "B2B-RX Test Finished.", UVM_MEDIUM)
    phase.drop_objection(this);
  endtask
endclass
