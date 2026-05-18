// delayed_crc_rx_test.sv - Test for delayed CRC checking with DlyCrcEn enabled/disabled
class delayed_crc_rx_test extends base_test;
  `uvm_component_utils(delayed_crc_rx_test)

  function new(string name="delayed_crc_rx_test", uvm_component parent=null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    // Disable scoreboard - using BD-level verification
    uvm_config_db#(bit)::set(this, "m_env.m_scoreboard", "disable_rx_check", 1);
  endfunction

  virtual task run_phase(uvm_phase phase);
    delayed_crc_rx_seq     host_seq;
    phy_delayed_crc_seq    phy_seq;

    phase.raise_objection(this);

    `uvm_info(get_type_name(), "Starting DELAYED-CRC-RX: Delayed CRC Reception Test", UVM_MEDIUM)

    // Wait for Reset
    wait (m_host_cfg.vif.rst === 1'b0);
    #1000ns;

    host_seq = delayed_crc_rx_seq::type_id::create("host_seq");
    phy_seq  = phy_delayed_crc_seq::type_id::create("phy_seq");

    // Randomize PHY sequence - using custom sequence for delayed CRC test
    if (!phy_seq.randomize() with {num_packets == 4;}) begin
      `uvm_fatal(get_type_name(), "Failed to randomize phy_delayed_crc_seq")
    end

    `uvm_info(get_type_name(), $sformatf("Configured to send %0d packets", phy_seq.num_packets), UVM_MEDIUM)

    // Run test - exactly matching huge_rx_test timing
    fork
      begin
        // Host sequence controls both phases
        host_seq.start(m_env.m_host_agent.m_sequencer); 
      end
      
      begin
        // Wait for Phase 1 configuration, then send packets
        #12000ns;
        `uvm_info("TEST", "Sending packets for Phase 1 (DlyCrcEn=0)...", UVM_MEDIUM)
        phy_seq.start(m_env.m_phy_agent.m_sequencer);
        
        // Wait for Phase 2 configuration, then send packets again
        #200000ns;
        `uvm_info("TEST", "Sending packets for Phase 2 (DlyCrcEn=1)...", UVM_MEDIUM)
        phy_seq.start(m_env.m_phy_agent.m_sequencer);
      end
    join 

    // Drain time
    #5000ns; 

    `uvm_info(get_type_name(), "DELAYED-CRC-RX Test Finished.", UVM_MEDIUM)
    phase.drop_objection(this);
  endtask
endclass
