// base_rx_test.sv - Test for receiving maximum-length packets
class base_rx_test extends base_test;
  `uvm_component_utils(base_rx_test)

  function new(string name="base_rx_test", uvm_component parent=null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    base_rx_seq         host_seq;
    phy_max_packet_seq  phy_seq;

    phase.raise_objection(this);

    `uvm_info(get_type_name(), "Starting BASE-RX: Maximum-Length Packet Receive (1518 bytes)", UVM_MEDIUM)

    // Wait for Reset
    `uvm_info(get_type_name(), "Waiting for Reset...", UVM_MEDIUM)
    wait (m_host_cfg.vif.rst === 1'b0);
    `uvm_info(get_type_name(), "Reset Released. Starting Test...", UVM_MEDIUM)
    
    // Initial stabilization
    #1000ns;

    host_seq = base_rx_seq        ::type_id::create("host_seq");
    phy_seq  = phy_max_packet_seq ::type_id::create("phy_seq");

    fork
      begin
        // Delay to ensure host configuration completes before packet transmission
        #10000ns; 
        `uvm_info("TEST", "Triggering PHY Sequence (Max Packet)...", UVM_MEDIUM)
        phy_seq.start(m_env.m_phy_agent.m_sequencer); 
      end
      
      begin
        // Host Sequence: Configures -> Waits for PHY event -> Polls
        host_seq.start(m_env.m_host_agent.m_sequencer); 
      end
    join 

    // Drain time for Scoreboard
    #2000ns; 

    `uvm_info(get_type_name(), "BASE-RX Test Finished.", UVM_MEDIUM)
    phase.drop_objection(this);
  endtask
endclass
