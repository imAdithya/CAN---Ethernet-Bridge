// bridge_filter_seq.sv — Filter test sequences for bridge testbench
// Covers tests: FLT-01, FLT-02


// =========================================================================
// FLT-01: Accept List Mode
// Configure filter in accept mode, verify matching IDs pass and
// non-matching IDs are dropped (cnt_filtered increments)
// =========================================================================
class filter_accept_seq extends uvm_sequence #(wishbone_transaction);
  `uvm_object_utils(filter_accept_seq)

  bridge_reg_write_seq wr_seq;
  bridge_reg_read_seq  rd_seq;

  // CAN IDs to test
  bit [28:0] accept_id  = 29'h123;   // This ID is in the table → pass
  bit [28:0] reject_id  = 29'h456;   // This ID is NOT in table → drop

  function new(string name = "filter_accept_seq");
    super.new(name);
  endfunction

  virtual task body();
    `uvm_info(get_type_name(), "Starting filter accept-list test (FLT-01)...", UVM_MEDIUM)

    wr_seq = bridge_reg_write_seq::type_id::create("wr_seq");
    rd_seq = bridge_reg_read_seq::type_id::create("rd_seq");

    // Step 1: Configure bridge in gateway mode, enabled
    wr_seq.addr = {24'h0, `REG_BRIDGE_CTRL};
    wr_seq.data = 32'h0000_0003;  // enable=1, mode=gateway(01)
    wr_seq.start(m_sequencer);

    // Step 2: Write accept_id into filter table entry 0
    wr_seq.addr = {24'h0, `REG_FILTER_TBL_BASE};  // filter_table[0]
    wr_seq.data = {3'h0, accept_id};
    wr_seq.start(m_sequencer);

    // Step 3: Clear remaining filter entries (write 0)
    for (int i = 1; i < 16; i++) begin
      wr_seq.addr = {24'h0, `REG_FILTER_TBL_BASE + i * 4};
      wr_seq.data = 32'h0;
      wr_seq.start(m_sequencer);
    end

    // Step 4: Enable filter in accept-list mode (filter_en=1, filter_mode=0)
    wr_seq.addr = {24'h0, `REG_FILTER_CTRL};
    wr_seq.data = 32'h0000_0001;  // {mode=0, enable=1}
    wr_seq.start(m_sequencer);

    // Step 5: Read back filter config to verify
    rd_seq.addr = {24'h0, `REG_FILTER_CTRL};
    rd_seq.start(m_sequencer);
    if (rd_seq.data !== 32'h0000_0001)
      `uvm_error("FLT_ACCEPT", $sformatf(
        "FILTER_CTRL mismatch: expected=0x01, got=0x%08h", rd_seq.data))

    rd_seq.addr = {24'h0, `REG_FILTER_TBL_BASE};
    rd_seq.start(m_sequencer);
    if (rd_seq.data !== {3'h0, accept_id})
      `uvm_error("FLT_ACCEPT", $sformatf(
        "FILTER_TBL[0] mismatch: expected=0x%08h, got=0x%08h",
        {3'h0, accept_id}, rd_seq.data))

    // Step 6: Read cnt_filtered baseline
    rd_seq.addr = {24'h0, `REG_CNT_FILTERED};
    rd_seq.start(m_sequencer);
    `uvm_info("FLT_ACCEPT", $sformatf(
      "Baseline cnt_filtered = %0d", rd_seq.data), UVM_MEDIUM)

    // NOTE: Actual CAN frame injection and IRQ triggering happens in the
    // test class, which coordinates with the CAN agent to load frames
    // and assert can_rx_irq. The test will:
    //   1. Load accept_id frame → trigger IRQ → verify cnt_can_rx++, cnt_eth_tx++
    //   2. Load reject_id frame → trigger IRQ → verify cnt_filtered++

    `uvm_info(get_type_name(),
      "Filter accept-list configuration complete. Ready for frame injection.",
      UVM_MEDIUM)
  endtask
endclass

// =========================================================================
// FLT-02: Reject List Mode
// Configure filter in reject mode, verify matching IDs are dropped
// and non-matching IDs pass
// =========================================================================
class filter_reject_seq extends uvm_sequence #(wishbone_transaction);
  `uvm_object_utils(filter_reject_seq)

  bridge_reg_write_seq wr_seq;
  bridge_reg_read_seq  rd_seq;

  // CAN IDs to test
  bit [28:0] reject_id = 29'h7FF;   // This ID is in the reject table → drop
  bit [28:0] pass_id   = 29'h100;   // This ID is NOT in table → pass

  function new(string name = "filter_reject_seq");
    super.new(name);
  endfunction

  virtual task body();
    `uvm_info(get_type_name(), "Starting filter reject-list test (FLT-02)...", UVM_MEDIUM)

    wr_seq = bridge_reg_write_seq::type_id::create("wr_seq");
    rd_seq = bridge_reg_read_seq::type_id::create("rd_seq");

    // Step 1: Configure bridge enabled, gateway mode
    wr_seq.addr = {24'h0, `REG_BRIDGE_CTRL};
    wr_seq.data = 32'h0000_0003;
    wr_seq.start(m_sequencer);

    // Step 2: Write reject_id into filter table entry 0
    wr_seq.addr = {24'h0, `REG_FILTER_TBL_BASE};
    wr_seq.data = {3'h0, reject_id};
    wr_seq.start(m_sequencer);

    // Step 3: Clear remaining entries
    for (int i = 1; i < 16; i++) begin
      wr_seq.addr = {24'h0, `REG_FILTER_TBL_BASE + i * 4};
      wr_seq.data = 32'h0;
      wr_seq.start(m_sequencer);
    end

    // Step 4: Enable filter in REJECT-list mode (filter_en=1, filter_mode=1)
    wr_seq.addr = {24'h0, `REG_FILTER_CTRL};
    wr_seq.data = 32'h0000_0003;  // {mode=1, enable=1}
    wr_seq.start(m_sequencer);

    // Step 5: Verify config
    rd_seq.addr = {24'h0, `REG_FILTER_CTRL};
    rd_seq.start(m_sequencer);
    if (rd_seq.data !== 32'h0000_0003)
      `uvm_error("FLT_REJECT", $sformatf(
        "FILTER_CTRL mismatch: expected=0x03, got=0x%08h", rd_seq.data))

    `uvm_info(get_type_name(),
      "Filter reject-list configuration complete. Ready for frame injection.",
      UVM_MEDIUM)

    // Test logic:
    //   1. Load reject_id frame → trigger IRQ → filter matches → DROP
    //      - cnt_can_rx++, cnt_filtered++, cnt_eth_tx stays same
    //   2. Load pass_id frame → trigger IRQ → no match in reject list → PASS
    //      - cnt_can_rx++, cnt_eth_tx++
  endtask
endclass

// =========================================================================
// Helper: Bridge Config Sequence (used by many test sequences)
// Configures bridge with specified mode, filter, and MAC addresses
// =========================================================================
class bridge_config_seq extends uvm_sequence #(wishbone_transaction);
  `uvm_object_utils(bridge_config_seq)

  bridge_reg_write_seq wr_seq;

  // Config parameters (set by test before starting)
  bit [1:0]  mode       = 2'b01;     // gateway default
  bit        enable     = 1;
  bit        filter_en  = 0;
  bit        filter_mode = 0;
  bit [31:0] dst_mac_hi = `DEFAULT_DST_MAC_HI;
  bit [31:0] dst_mac_lo = `DEFAULT_DST_MAC_LO;
  bit [31:0] src_mac_hi = `DEFAULT_SRC_MAC_HI;
  bit [31:0] src_mac_lo = `DEFAULT_SRC_MAC_LO;
  bit [31:0] tx_bd_addr = `DEFAULT_TX_BD_ADDR;
  bit [31:0] rx_bd_addr = `DEFAULT_RX_BD_ADDR;

  function new(string name = "bridge_config_seq");
    super.new(name);
  endfunction

  virtual task body();
    wr_seq = bridge_reg_write_seq::type_id::create("wr_seq");

    `uvm_info(get_type_name(), $sformatf(
      "Configuring bridge: en=%0b mode=%02b filter_en=%0b",
      enable, mode, filter_en), UVM_MEDIUM)

    // BRIDGE_CTRL: {mode[2:1], enable[0]}
    wr_seq.addr = {24'h0, `REG_BRIDGE_CTRL};
    wr_seq.data = {29'h0, mode, enable};
    wr_seq.start(m_sequencer);

    // MAC addresses
    wr_seq.addr = {24'h0, `REG_DST_MAC_HI}; wr_seq.data = dst_mac_hi;
    wr_seq.start(m_sequencer);
    wr_seq.addr = {24'h0, `REG_DST_MAC_LO}; wr_seq.data = dst_mac_lo;
    wr_seq.start(m_sequencer);
    wr_seq.addr = {24'h0, `REG_SRC_MAC_HI}; wr_seq.data = src_mac_hi;
    wr_seq.start(m_sequencer);
    wr_seq.addr = {24'h0, `REG_SRC_MAC_LO}; wr_seq.data = src_mac_lo;
    wr_seq.start(m_sequencer);

    // Filter
    wr_seq.addr = {24'h0, `REG_FILTER_CTRL};
    wr_seq.data = {30'h0, filter_mode, filter_en};
    wr_seq.start(m_sequencer);

    // BD addresses
    wr_seq.addr = {24'h0, `REG_TX_BD_ADDR}; wr_seq.data = tx_bd_addr;
    wr_seq.start(m_sequencer);
    wr_seq.addr = {24'h0, `REG_RX_BD_ADDR}; wr_seq.data = rx_bd_addr;
    wr_seq.start(m_sequencer);

    `uvm_info(get_type_name(), "Bridge configuration complete.", UVM_MEDIUM)
  endtask
endclass
