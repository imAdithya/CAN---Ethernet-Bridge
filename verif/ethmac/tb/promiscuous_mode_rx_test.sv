// promiscuous_mode_rx_test.sv - Test for promiscuous mode reception
class promiscuous_mode_rx_test extends base_test;
  `uvm_component_utils(promiscuous_mode_rx_test)

  function new(string name="promiscuous_mode_rx_test", uvm_component parent=null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    // Disable scoreboard - BD-level verification in promiscuous_mode_seq
    uvm_config_db#(bit)::set(this, "m_env.m_scoreboard", "disable_rx_check", 1);
  endfunction

  virtual task run_phase(uvm_phase phase);
    promiscuous_mode_seq  host_seq;
    phy_promisc_seq       phy_seq;

    phase.raise_objection(this);

    `uvm_info(get_type_name(), "Starting PROMISC-RX: Promiscuous Mode Reception Test", UVM_MEDIUM)

    // Wait for Reset
    wait (m_host_cfg.vif.rst === 1'b0);
    #1000ns;

    host_seq = promiscuous_mode_seq::type_id::create("host_seq");
    phy_seq  = phy_promisc_seq::type_id::create("phy_seq");

    fork
      begin
        // Host sequence drives all 3 phases
        host_seq.start(m_env.m_host_agent.m_sequencer);
      end

      begin
        // Phase 1: PRO=0, mixed MACs
        #12000ns;
        `uvm_info("TEST", "Phase 1: Sending mixed-MAC packets (PRO=0)...", UVM_MEDIUM)
        phy_seq.mode = 0;
        phy_seq.start(m_env.m_phy_agent.m_sequencer);

        // Phase 2: PRO=1, mixed MACs
        #200000ns;
        `uvm_info("TEST", "Phase 2: Sending mixed-MAC packets (PRO=1)...", UVM_MEDIUM)
        phy_seq.mode = 0;
        phy_seq.start(m_env.m_phy_agent.m_sequencer);

        // Phase 3: PRO=1, all non-matching
        #200000ns;
        `uvm_info("TEST", "Phase 3: Sending non-matching packets (PRO=1)...", UVM_MEDIUM)
        phy_seq.mode = 1;
        phy_seq.start(m_env.m_phy_agent.m_sequencer);
      end
    join

    // Drain time
    #5000ns;

    `uvm_info(get_type_name(), "PROMISC-RX Test Finished.", UVM_MEDIUM)
    phase.drop_objection(this);
  endtask
endclass
