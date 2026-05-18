// addr_match_rx_test.sv - Test for individual/multicast address matching
class addr_match_rx_test extends base_test;
  `uvm_component_utils(addr_match_rx_test)

  function new(string name="addr_match_rx_test", uvm_component parent=null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    uvm_config_db#(bit)::set(this, "m_env.m_scoreboard", "disable_rx_check", 1);
  endfunction

  virtual task run_phase(uvm_phase phase);
    addr_match_rx_seq    host_seq;
    phy_addr_match_seq   phy_seq;

    phase.raise_objection(this);

    `uvm_info(get_type_name(), "Starting ADDR-MATCH-RX: Address Matching Test", UVM_MEDIUM)

    wait (m_host_cfg.vif.rst === 1'b0);
    #1000ns;

    host_seq = addr_match_rx_seq::type_id::create("host_seq");
    phy_seq  = phy_addr_match_seq::type_id::create("phy_seq");

    fork
      begin
        host_seq.start(m_env.m_host_agent.m_sequencer);
      end

      begin
        // Phase 1: r_Bro=0, HASH=0
        #12000ns;
        `uvm_info("TEST", "Phase 1: Sending 4 packets (r_Bro=0, HASH=0)...", UVM_MEDIUM)
        phy_seq.start(m_env.m_phy_agent.m_sequencer);

        // Phase 2: r_Bro=1, HASH=0
        #200000ns;
        `uvm_info("TEST", "Phase 2: Sending 4 packets (r_Bro=1, HASH=0)...", UVM_MEDIUM)
        phy_seq.start(m_env.m_phy_agent.m_sequencer);

        // Phase 3: r_Bro=0, HASH=all-1s
        #200000ns;
        `uvm_info("TEST", "Phase 3: Sending 4 packets (HASH=all-1s)...", UVM_MEDIUM)
        phy_seq.start(m_env.m_phy_agent.m_sequencer);

        // Phase 4: r_Bro=0, HASH=specific-wrong
        #200000ns;
        `uvm_info("TEST", "Phase 4: Sending 4 packets (HASH=specific-wrong)...", UVM_MEDIUM)
        phy_seq.start(m_env.m_phy_agent.m_sequencer);
      end
    join

    #5000ns;
    `uvm_info(get_type_name(), "ADDR-MATCH-RX Test Finished.", UVM_MEDIUM)
    phase.drop_objection(this);
  endtask
endclass
