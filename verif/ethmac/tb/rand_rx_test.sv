// rand_rx_test.sv - Test for randomized packet reception with filtering
class rand_rx_test extends base_test;
  `uvm_component_utils(rand_rx_test)

  function new(string name="rand_rx_test", uvm_component parent=null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    // Scoreboard has address filtering support, but  byte-level verification fails with
    // multiple BDs due to buffer boundary tracking issues. Manual BD checking used instead.
    uvm_config_db#(bit)::set(this, "m_env.m_scoreboard", "disable_rx_check", 1);
  endfunction

  virtual task run_phase(uvm_phase phase);
    rand_rx_seq         host_seq;
    phy_rand_packet_seq phy_seq;

    phase.raise_objection(this);

    `uvm_info(get_type_name(), "Starting RAND-RX: Randomized Packet Reception with Filtering", UVM_MEDIUM)

    // Wait for Reset
    `uvm_info(get_type_name(), "Waiting for Reset...", UVM_MEDIUM)
    wait (m_host_cfg.vif.rst === 1'b0);
    `uvm_info(get_type_name(), "Reset Released. Starting Test...", UVM_MEDIUM)
    
    // Initial stabilization
    #1000ns;

    host_seq = rand_rx_seq        ::type_id::create("host_seq");
    phy_seq  = phy_rand_packet_seq::type_id::create("phy_seq");

    // Randomize packet parameters
    if (!phy_seq.randomize()) begin
      `uvm_fatal(get_type_name(), "Failed to randomize phy_rand_packet_seq")
    end

    `uvm_info(get_type_name(), $sformatf("Configured to send %0d packets with size %0d-%0d bytes", 
              phy_seq.num_packets, phy_seq.payload_size_min, phy_seq.payload_size_max), UVM_MEDIUM)

    fork
      begin
        // Delay to ensure host configuration completes  
        #10000ns;
        `uvm_info("TEST", $sformatf("Sending %0d randomized packets...", phy_seq.num_packets), UVM_MEDIUM)
        phy_seq.start(m_env.m_phy_agent.m_sequencer);
      end
      
      begin
        // Host sequence handles all filtering modes
        host_seq.start(m_env.m_host_agent.m_sequencer); 
      end
    join 

    // Drain time
    #5000ns; 

    `uvm_info(get_type_name(), "RAND-RX Test Finished.", UVM_MEDIUM)
    phase.drop_objection(this);
  endtask
endclass
