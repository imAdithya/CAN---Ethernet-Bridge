// UP-05: Filter Drop Upstream Test
// Sends a CAN frame that gets rejected by the accept-list filter.
// Verifies: FSM IDLE->READ_CAN->FILTER->IDLE (skips ENCAP onwards),
// no RAM write, no BD program, cnt_filtered increments.
class upstream_filter_drop_test extends bridge_base_test;
  `uvm_component_utils(upstream_filter_drop_test)

  function new(string name = "upstream_filter_drop_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    upstream_filter_drop_seq up_seq;
    counter_verify_seq       cnt_seq;
    bit [31:0] bd_before, ram_before;
    bit [31:0] bd_after, ram_after;

    phase.raise_objection(this);

    `uvm_info(get_type_name(), "Starting filter drop upstream test (UP-05)...", UVM_MEDIUM)
    #100ns;

    // Step 1: Configure bridge + filter (accept_id=0x100, filter enabled)
    up_seq = upstream_filter_drop_seq::type_id::create("up_seq");
    up_seq.start(m_env.m_host_agent.m_sequencer);

    // Step 2: Record memory state before frame (BD and RAM area)
    bd_before  = m_mem_cfg.memory[`DEFAULT_TX_BD_ADDR >> 2];
    ram_before = m_mem_cfg.memory[(`DEFAULT_TX_BD_ADDR + 32'h400) >> 2];

    // Step 3: Load CAN frame with ID NOT in accept list -> should be dropped
    m_can_cfg.load_can_frame(
      .can_id(29'h7FF), .dlc(4'd4), .eff(1'b0), .rtr(1'b0),
      .data('{8'hDD, 8'hEE, 8'hAA, 8'hDD, 8'h00, 8'h00, 8'h00, 8'h00})
    );

    m_can_cfg.vif.can_rx_irq = 1'b1;
    #40ns;
    m_can_cfg.vif.can_rx_irq = 1'b0;

    // Wait for filter decision + return to IDLE
    #5us;

    // Step 4: Verify NO RAM write occurred
    bd_after  = m_mem_cfg.memory[`DEFAULT_TX_BD_ADDR >> 2];
    ram_after = m_mem_cfg.memory[(`DEFAULT_TX_BD_ADDR + 32'h400) >> 2];

    if (bd_after !== bd_before)
      `uvm_error("UP05_CHK", $sformatf(
        "BD was modified after filter drop: before=0x%08h after=0x%08h",
        bd_before, bd_after))
    else
      `uvm_info("UP05_CHK", "No BD write after filter drop PASS", UVM_MEDIUM)

    if (ram_after !== ram_before)
      `uvm_error("UP05_CHK", $sformatf(
        "RAM was modified after filter drop: before=0x%08h after=0x%08h",
        ram_before, ram_after))
    else
      `uvm_info("UP05_CHK", "No RAM write after filter drop PASS", UVM_MEDIUM)

    // Step 5: Verify counters — 1 frame read, 0 forwarded, 1 filtered
    cnt_seq = counter_verify_seq::type_id::create("cnt_seq");
    cnt_seq.exp_can_rx   = 1;
    cnt_seq.exp_eth_tx   = 0;
    cnt_seq.exp_filtered = 1;
    cnt_seq.start(m_env.m_host_agent.m_sequencer);

    #500ns;
    `uvm_info(get_type_name(), "UP-05 finished.", UVM_MEDIUM)
    phase.drop_objection(this);
  endtask
endclass
