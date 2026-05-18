class rx_simple_test extends base_test;
  `uvm_component_utils(rx_simple_test)

  function new(string name="rx_simple_test", uvm_component parent=null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    rx_host_seq     host_seq;
    phy_packet_seq  phy_seq;

    phase.raise_objection(this);

    `uvm_info(get_type_name(), "Starting RX-01: Single Packet Receive", UVM_MEDIUM)

    // Wait for Reset
    `uvm_info(get_type_name(), "Waiting for Reset...", UVM_MEDIUM)
    wait (m_host_cfg.vif.rst === 1'b0);
    `uvm_info(get_type_name(), "Reset Released. Starting Test...", UVM_MEDIUM)
    
    // Initial stabilization
    #1000ns;

    host_seq = rx_host_seq    ::type_id::create("host_seq");
    phy_seq  = phy_packet_seq ::type_id::create("phy_seq");

    fork
      begin
        // [FIX]: Increased delay to 10,000ns (10us).
        // This ensures host_seq has definitely finished Steps 1-8 (Config & Enable)
        // before we put a packet on the wire.
        #10000ns; 
        `uvm_info("TEST", "Triggering PHY Sequence now...", UVM_MEDIUM)
        phy_seq.start(m_env.m_phy_agent.m_sequencer); 
      end
      
      begin
        // Host Sequence: Configures -> Waits for PHY event -> Polls
        host_seq.start(m_env.m_host_agent.m_sequencer); 
      end
    join 

    // Drain time for Scoreboard
    #2000ns; 

    `uvm_info(get_type_name(), "RX-01 Test Finished.", UVM_MEDIUM)
    phase.drop_objection(this);
  endtask
endclass