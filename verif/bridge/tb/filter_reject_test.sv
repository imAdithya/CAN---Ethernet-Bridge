// FLT-02: Filter Reject List Test
class filter_reject_test extends bridge_base_test;
  `uvm_component_utils(filter_reject_test)

  function new(string name = "filter_reject_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    filter_reject_seq  flt_seq;
    counter_verify_seq cnt_seq;
    phase.raise_objection(this);

    `uvm_info(get_type_name(), "Starting filter reject-list test (FLT-02)...", UVM_MEDIUM)
    #100ns;

    // Step 1: Configure filter in reject mode
    flt_seq = filter_reject_seq::type_id::create("flt_seq");
    flt_seq.reject_id = 29'h7FF;
    flt_seq.pass_id   = 29'h100;
    flt_seq.start(m_env.m_host_agent.m_sequencer);

    // Step 2: Load MATCHING CAN frame (ID=0x7FF) → should be REJECTED
    m_can_cfg.load_can_frame(
      .can_id(29'h7FF), .dlc(4'd2), .eff(1'b0), .rtr(1'b0),
      .data('{8'hDE, 8'hAD, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00})
    );

    m_can_cfg.vif.can_rx_irq = 1'b1;
    #40ns;
    m_can_cfg.vif.can_rx_irq = 1'b0;
    #5us;

    // Step 3: Load NON-matching CAN frame (ID=0x100) → should PASS
    m_can_cfg.load_can_frame(
      .can_id(29'h100), .dlc(4'd8), .eff(1'b0), .rtr(1'b0),
      .data('{8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08})
    );

    m_can_cfg.vif.can_rx_irq = 1'b1;
    #40ns;
    m_can_cfg.vif.can_rx_irq = 1'b0;
    #10us;

    // Simulate ETH TX complete for the passed frame
    m_mem_cfg.vif.eth_tx_irq = 1'b1;
    #40ns;
    m_mem_cfg.vif.eth_tx_irq = 1'b0;
    #2us;

    // Step 4: Verify counters (reject mode = inverted logic)
    cnt_seq = counter_verify_seq::type_id::create("cnt_seq");
    cnt_seq.exp_can_rx   = 2;  // Both read
    cnt_seq.exp_eth_tx   = 1;  // Only non-matching passed
    cnt_seq.exp_filtered = 1;  // Matching ID was rejected
    cnt_seq.start(m_env.m_host_agent.m_sequencer);

    #500ns;
    `uvm_info(get_type_name(), "FLT-02 finished.", UVM_MEDIUM)
    phase.drop_objection(this);
  endtask
endclass
