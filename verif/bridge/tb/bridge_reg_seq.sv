// bridge_reg_seq.sv — Register access sequences for bridge testbench
// Covers tests: REG-01, REG-02, CNT-01, MODE-01, MODE-02


// =========================================================================
// Low-level helpers: bridge register write/read
// =========================================================================
class bridge_reg_write_seq extends uvm_sequence #(wishbone_transaction);
  `uvm_object_utils(bridge_reg_write_seq)

  bit [31:0] addr;
  bit [31:0] data;

  function new(string name = "bridge_reg_write_seq");
    super.new(name);
  endfunction

  virtual task body();
    wishbone_transaction req;
    req = wishbone_transaction::type_id::create("req");
    start_item(req);
    assert(req.randomize() with {
      address    == local::addr;
      write_data == local::data;
      is_read    == 1'b0;
      sel        == 4'hF;
    });
    finish_item(req);
  endtask
endclass

class bridge_reg_read_seq extends uvm_sequence #(wishbone_transaction);
  `uvm_object_utils(bridge_reg_read_seq)

  bit [31:0] addr;
  bit [31:0] data;   // Output: read data

  function new(string name = "bridge_reg_read_seq");
    super.new(name);
  endfunction

  virtual task body();
    wishbone_transaction req, rsp;
    req = wishbone_transaction::type_id::create("req");
    start_item(req);
    assert(req.randomize() with {
      address == local::addr;
      is_read == 1'b1;
      sel     == 4'hF;
    });
    finish_item(req);
    get_response(rsp);
    data = rsp.read_data;
  endtask
endclass

// =========================================================================
// REG-01: Register Access Sequence
// Write/read all R/W registers with various patterns
// =========================================================================
class bridge_reg_access_seq extends uvm_sequence #(wishbone_transaction);
  `uvm_object_utils(bridge_reg_access_seq)

  bridge_reg_write_seq wr_seq;
  bridge_reg_read_seq  rd_seq;

  // R/W register addresses
  bit [7:0] rw_addrs[] = '{
    `REG_BRIDGE_CTRL, `REG_DST_MAC_HI, `REG_DST_MAC_LO,
    `REG_SRC_MAC_HI,  `REG_SRC_MAC_LO, `REG_FILTER_CTRL,
    `REG_TX_BD_ADDR,   `REG_RX_BD_ADDR
  };

  // Test patterns
  bit [31:0] patterns[] = '{32'h0000_0000, 32'hFFFF_FFFF, 32'hA5A5_A5A5, 32'h5A5A_5A5A};

  function new(string name = "bridge_reg_access_seq");
    super.new(name);
  endfunction

  virtual task body();
    `uvm_info(get_type_name(), "Starting bridge register access test...", UVM_MEDIUM)

    wr_seq = bridge_reg_write_seq::type_id::create("wr_seq");
    rd_seq = bridge_reg_read_seq::type_id::create("rd_seq");

    // Test each R/W register with each pattern
    foreach (rw_addrs[i]) begin
      foreach (patterns[j]) begin
        // Write pattern
        wr_seq.addr = {24'h0, rw_addrs[i]};
        wr_seq.data = patterns[j];
        wr_seq.start(m_sequencer);

        // Read back
        rd_seq.addr = {24'h0, rw_addrs[i]};
        rd_seq.start(m_sequencer);

        // Check
        if (rd_seq.data !== patterns[j])
          `uvm_error("REG_ACCESS", $sformatf(
            "MISMATCH @0x%02h: wrote=0x%08h read=0x%08h",
            rw_addrs[i], patterns[j], rd_seq.data))
        else
          `uvm_info("REG_ACCESS", $sformatf(
            "PASS @0x%02h: 0x%08h", rw_addrs[i], rd_seq.data), UVM_HIGH)
      end
    end

    // Also test all 16 filter table entries
    for (int k = 0; k < 16; k++) begin
      wr_seq.addr = {24'h0, `REG_FILTER_TBL_BASE + k * 4};
      wr_seq.data = {3'h0, 29'(k * 'h111)};  // Unique ID per entry
      wr_seq.start(m_sequencer);

      rd_seq.addr = wr_seq.addr;
      rd_seq.start(m_sequencer);

      if (rd_seq.data !== wr_seq.data)
        `uvm_error("REG_ACCESS", $sformatf(
          "FILTER_TBL[%0d] MISMATCH: wrote=0x%08h read=0x%08h",
          k, wr_seq.data, rd_seq.data))
    end

    // Read status register (read-only) to hit coverage
    rd_seq.addr = {24'h0, `REG_BRIDGE_STATUS};
    rd_seq.start(m_sequencer);
    `uvm_info("REG_ACCESS", $sformatf("STATUS register = 0x%08h", rd_seq.data), UVM_MEDIUM)

    `uvm_info(get_type_name(), "Register access test finished.", UVM_MEDIUM)
  endtask
endclass

// =========================================================================
// REG-02: Reset Default Values Sequence
// Read all registers after reset, verify hybrid defaults
// =========================================================================
class bridge_reg_reset_seq extends uvm_sequence #(wishbone_transaction);
  `uvm_object_utils(bridge_reg_reset_seq)

  bridge_reg_read_seq rd_seq;

  function new(string name = "bridge_reg_reset_seq");
    super.new(name);
  endfunction

  virtual task body();
    bit [7:0]  addrs[];
    bit [31:0] expected[];
    int        errors = 0;

    `uvm_info(get_type_name(), "Starting reset default value check...", UVM_MEDIUM)

    rd_seq = bridge_reg_read_seq::type_id::create("rd_seq");

    // Expected reset values from can_eth_bridge_defines.v
    addrs    = '{`REG_BRIDGE_CTRL, `REG_DST_MAC_HI, `REG_DST_MAC_LO,
                 `REG_SRC_MAC_HI,  `REG_SRC_MAC_LO, `REG_FILTER_CTRL,
                 `REG_TX_BD_ADDR,  `REG_RX_BD_ADDR,
                 `REG_CNT_CAN_RX,  `REG_CNT_ETH_TX, `REG_CNT_FILTERED,
                 `REG_CNT_ERRORS,  `REG_TUNNEL_SEQ};

    expected = '{`DEFAULT_BRIDGE_CTRL, `DEFAULT_DST_MAC_HI, `DEFAULT_DST_MAC_LO,
                 `DEFAULT_SRC_MAC_HI,  `DEFAULT_SRC_MAC_LO, `DEFAULT_FILTER_CTRL,
                 `DEFAULT_TX_BD_ADDR,  `DEFAULT_RX_BD_ADDR,
                 32'h0, 32'h0, 32'h0, 32'h0, 32'h0};

    foreach (addrs[i]) begin
      rd_seq.addr = {24'h0, addrs[i]};
      rd_seq.start(m_sequencer);

      if (rd_seq.data !== expected[i]) begin
        `uvm_error("RESET_CHK", $sformatf(
          "FAIL @0x%02h: expected=0x%08h actual=0x%08h",
          addrs[i], expected[i], rd_seq.data))
        errors++;
      end else begin
        `uvm_info("RESET_CHK", $sformatf(
          "PASS @0x%02h = 0x%08h", addrs[i], rd_seq.data), UVM_HIGH)
      end
    end

    if (errors == 0)
      `uvm_info(get_type_name(), "All reset defaults PASS.", UVM_MEDIUM)
    else
      `uvm_error(get_type_name(), $sformatf("%0d reset default failures.", errors))
  endtask
endclass

// =========================================================================
// CNT-01: Counter Verification Sequence
// Read all 6 counters and verify against expected values
// =========================================================================
class counter_verify_seq extends uvm_sequence #(wishbone_transaction);
  `uvm_object_utils(counter_verify_seq)

  bridge_reg_read_seq rd_seq;

  // Expected values (set by the test before starting this sequence)
  int exp_can_rx   = 0;
  int exp_eth_tx   = 0;
  int exp_eth_rx   = 0;
  int exp_can_tx   = 0;
  int exp_filtered = 0;
  int exp_errors   = 0;

  function new(string name = "counter_verify_seq");
    super.new(name);
  endfunction

  virtual task body();
    int fail_count = 0;

    `uvm_info(get_type_name(), "Verifying status counters...", UVM_MEDIUM)

    rd_seq = bridge_reg_read_seq::type_id::create("rd_seq");

    // Read and check each counter
    check_counter(`REG_CNT_CAN_RX,   "cnt_can_rx",   exp_can_rx,   fail_count);
    check_counter(`REG_CNT_ETH_TX,   "cnt_eth_tx",   exp_eth_tx,   fail_count);
    check_counter(`REG_CNT_ETH_RX,   "cnt_eth_rx",   exp_eth_rx,   fail_count);
    check_counter(`REG_CNT_CAN_TX,   "cnt_can_tx",   exp_can_tx,   fail_count);
    check_counter(`REG_CNT_FILTERED, "cnt_filtered", exp_filtered, fail_count);
    check_counter(`REG_CNT_ERRORS,   "cnt_errors",   exp_errors,   fail_count);

    if (fail_count == 0)
      `uvm_info(get_type_name(), "All counters PASS.", UVM_MEDIUM)
    else
      `uvm_error(get_type_name(), $sformatf("%0d counter mismatches.", fail_count))

    // Verify invariants
    if (exp_can_rx != (exp_eth_tx + exp_filtered))
      `uvm_warning("CNT_INV", $sformatf(
        "Upstream invariant broken: can_rx(%0d) != eth_tx(%0d) + filtered(%0d)",
        exp_can_rx, exp_eth_tx, exp_filtered))

    if (exp_eth_rx != (exp_can_tx + exp_errors))
      `uvm_warning("CNT_INV", $sformatf(
        "Downstream invariant broken: eth_rx(%0d) != can_tx(%0d) + errors(%0d)",
        exp_eth_rx, exp_can_tx, exp_errors))
  endtask

  task check_counter(bit [7:0] addr, string name, int expected,
                     ref int fail_count);
    rd_seq.addr = {24'h0, addr};
    rd_seq.start(m_sequencer);
    if (rd_seq.data !== expected) begin
      `uvm_error("CNT_CHK", $sformatf(
        "%s: expected=%0d actual=%0d", name, expected, rd_seq.data))
      fail_count++;
    end else
      `uvm_info("CNT_CHK", $sformatf("%s = %0d PASS", name, rd_seq.data), UVM_HIGH)
  endtask
endclass

// =========================================================================
// MODE-02: Bridge Disable Sequence
// Disable bridge, verify FSMs stay idle despite interrupts
// =========================================================================
class bridge_disable_seq extends uvm_sequence #(wishbone_transaction);
  `uvm_object_utils(bridge_disable_seq)

  bridge_reg_write_seq wr_seq;
  bridge_reg_read_seq  rd_seq;

  function new(string name = "bridge_disable_seq");
    super.new(name);
  endfunction

  virtual task body();
    `uvm_info(get_type_name(), "Testing bridge disable (bridge_en=0)...", UVM_MEDIUM)

    wr_seq = bridge_reg_write_seq::type_id::create("wr_seq");
    rd_seq = bridge_reg_read_seq::type_id::create("rd_seq");

    // Disable bridge
    wr_seq.addr = {24'h0, `REG_BRIDGE_CTRL};
    wr_seq.data = 32'h0000_0000;  // enable=0
    wr_seq.start(m_sequencer);

    // Wait for potential IRQ processing
    #5us;

    // Verify counters are all zero (no frames processed)
    rd_seq.addr = {24'h0, `REG_CNT_CAN_RX};
    rd_seq.start(m_sequencer);
    if (rd_seq.data != 0)
      `uvm_error("DISABLE", $sformatf("cnt_can_rx=%0d, expected 0", rd_seq.data))

    rd_seq.addr = {24'h0, `REG_CNT_ETH_RX};
    rd_seq.start(m_sequencer);
    if (rd_seq.data != 0)
      `uvm_error("DISABLE", $sformatf("cnt_eth_rx=%0d, expected 0", rd_seq.data))

    // Re-enable bridge for subsequent tests
    wr_seq.addr = {24'h0, `REG_BRIDGE_CTRL};
    wr_seq.data = `DEFAULT_BRIDGE_CTRL;
    wr_seq.start(m_sequencer);

    `uvm_info(get_type_name(), "Bridge disable test finished.", UVM_MEDIUM)
  endtask
endclass

// =========================================================================
// MODE-01: Mode Switch Sequence
// Switch between gateway and tunnel, verify via register readback
// =========================================================================
class mode_switch_seq extends uvm_sequence #(wishbone_transaction);
  `uvm_object_utils(mode_switch_seq)

  bridge_reg_write_seq wr_seq;
  bridge_reg_read_seq  rd_seq;

  function new(string name = "mode_switch_seq");
    super.new(name);
  endfunction

  virtual task body();
    `uvm_info(get_type_name(), "Testing mode switch (gateway <-> tunnel)...", UVM_MEDIUM)

    wr_seq = bridge_reg_write_seq::type_id::create("wr_seq");
    rd_seq = bridge_reg_read_seq::type_id::create("rd_seq");

    // Set gateway mode: enable=1, mode=01 → CTRL = 0x03
    wr_seq.addr = {24'h0, `REG_BRIDGE_CTRL};
    wr_seq.data = 32'h0000_0003;  // {mode=01, en=1}
    wr_seq.start(m_sequencer);

    rd_seq.addr = {24'h0, `REG_BRIDGE_CTRL};
    rd_seq.start(m_sequencer);
    if (rd_seq.data[2:1] !== 2'b01)
      `uvm_error("MODE", $sformatf("Gateway mode failed: CTRL=0x%08h", rd_seq.data))

    // Switch to tunnel mode: enable=1, mode=10 → CTRL = 0x05
    wr_seq.data = 32'h0000_0005;
    wr_seq.start(m_sequencer);

    rd_seq.start(m_sequencer);
    if (rd_seq.data[2:1] !== 2'b10)
      `uvm_error("MODE", $sformatf("Tunnel mode failed: CTRL=0x%08h", rd_seq.data))

    // Disabled + tunnel: en=0, mode=10 → CTRL = 0x04 (coverage: {disabled, tunnel})
    wr_seq.data = 32'h0000_0004;
    wr_seq.start(m_sequencer);

    // Switch back to gateway
    wr_seq.data = 32'h0000_0003;
    wr_seq.start(m_sequencer);

    `uvm_info(get_type_name(), "Mode switch test finished.", UVM_MEDIUM)
  endtask
endclass
