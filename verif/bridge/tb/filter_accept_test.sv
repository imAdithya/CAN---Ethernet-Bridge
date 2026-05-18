// FLT-01: Filter Accept List Test
class filter_accept_test extends bridge_base_test;
  `uvm_component_utils(filter_accept_test)

  function new(string name = "filter_accept_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    filter_accept_seq  flt_seq;
    counter_verify_seq cnt_seq;
    phase.raise_objection(this);

    `uvm_info(get_type_name(), "Starting filter accept-list test (FLT-01)...", UVM_MEDIUM)
    #100ns;

    // Step 1: Configure filter in accept mode
    flt_seq = filter_accept_seq::type_id::create("flt_seq");
    flt_seq.accept_id = 29'h123;
    flt_seq.reject_id = 29'h456;
    flt_seq.start(m_env.m_host_agent.m_sequencer);

    // Step 2: Load matching CAN frame (ID=0x123) into CAN agent
    m_can_cfg.load_can_frame(
      .can_id(29'h123), .dlc(4'd8), .eff(1'b0), .rtr(1'b0),
      .data('{8'hAA, 8'hBB, 8'hCC, 8'hDD, 8'hEE, 8'hFF, 8'h11, 8'h22})
    );

    // Step 3: Trigger CAN RX interrupt → bridge reads, filter PASSES
    m_can_cfg.vif.can_rx_irq = 1'b1;
    #40ns;
    m_can_cfg.vif.can_rx_irq = 1'b0;

    // Wait for upstream FSM to complete write to RAM
    #10us;

    // Simulate ETH TX complete
    m_mem_cfg.vif.eth_tx_irq = 1'b1;
    #40ns;
    m_mem_cfg.vif.eth_tx_irq = 1'b0;
    #2us;

    // Step 4: Load NON-matching CAN frame (ID=0x456) → should be FILTERED
    m_can_cfg.load_can_frame(
      .can_id(29'h456), .dlc(4'd4), .eff(1'b0), .rtr(1'b0),
      .data('{8'h01, 8'h02, 8'h03, 8'h04, 8'h00, 8'h00, 8'h00, 8'h00})
    );

    m_can_cfg.vif.can_rx_irq = 1'b1;
    #40ns;
    m_can_cfg.vif.can_rx_irq = 1'b0;

    // Wait for filter to reject
    #5us;

    // Step 5: Verify counters
    cnt_seq = counter_verify_seq::type_id::create("cnt_seq");
    cnt_seq.exp_can_rx   = 2;  // Both frames were read
    cnt_seq.exp_eth_tx   = 1;  // Only matching frame forwarded
    cnt_seq.exp_filtered = 1;  // Non-matching frame filtered
    cnt_seq.start(m_env.m_host_agent.m_sequencer);

    #500ns;
    `uvm_info(get_type_name(), "FLT-01 finished.", UVM_MEDIUM)
    phase.drop_objection(this);
  endtask
endclass
