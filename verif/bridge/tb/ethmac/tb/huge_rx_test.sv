// huge_rx_test.sv - Test for huge packet reception with HugEn enabled/disabled
class huge_rx_test extends base_test;
  `uvm_component_utils(huge_rx_test)

  function new(string name="huge_rx_test", uvm_component parent=null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    // Disable scoreboard - huge packets are truncated by hardware, causing byte mismatches
    // BD-level verification in huge_rx_seq is more appropriate
    uvm_config_db#(bit)::set(this, "m_env.m_scoreboard", "disable_rx_check", 1);
  endfunction

  virtual task run_phase(uvm_phase phase);
    huge_rx_seq         host_seq;
    phy_huge_packet_seq phy_seq;

    phase.raise_objection(this);

    `uvm_info(get_type_name(), "Starting HUGE-RX: Huge Packet Reception Test (HugEn)", UVM_MEDIUM)

    // Wait for Reset
    `uvm_info(get_type_name(), "Waiting for Reset...", UVM_MEDIUM)
    wait (m_host_cfg.vif.rst === 1'b0);
    `uvm_info(get_type_name(), "Reset Released. Starting Test...", UVM_MEDIUM)
    
    // Initial stabilization
    #1000ns;

    host_seq = huge_rx_seq        ::type_id::create("host_seq");
    phy_seq  = phy_huge_packet_seq::type_id::create("phy_seq");

    // Randomize PHY sequence for huge packets
    if (!phy_seq.randomize()) begin
      `uvm_fatal(get_type_name(), "Failed to randomize phy_huge_packet_seq")
    end

    `uvm_info(get_type_name(), $sformatf("Configured to send %0d huge packets with %0d byte payloads", 
              phy_seq.num_packets, phy_seq.huge_payload_size), UVM_MEDIUM)

    // Run test sequentially - host configures, then PHY sends packets
    fork
      begin
        // Host sequence controls both phases
        host_seq.start(m_env.m_host_agent.m_sequencer); 
      end
      
      begin
        // Wait for Phase 1 configuration, then send packets
        #12000ns;  // Wait for Phase 1 MAC config
        `uvm_info("TEST", "Sending huge packets for Phase 1 (HugEn=0)...", UVM_MEDIUM)
        phy_seq.start(m_env.m_phy_agent.m_sequencer);
        
        // Wait for Phase 2 configuration, then send packets again
        #200000ns;  // Wait for Phase 2
        `uvm_info("TEST", "Sending huge packets for Phase 2 (HugEn=1)...", UVM_MEDIUM)
        phy_seq.start(m_env.m_phy_agent.m_sequencer);
      end
    join 

    // Drain time
    #5000ns; 

    `uvm_info(get_type_name(), "HUGE-RX Test Finished.", UVM_MEDIUM)
    phase.drop_objection(this);
  endtask
endclass
