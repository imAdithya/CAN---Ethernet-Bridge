// bridge_upstream_seq.sv — Upstream test sequences (CAN → ETH)
// Covers tests: UP-01, UP-02, UP-03, UP-04, UP-05

// =========================================================================
// UP-01: Basic Gateway Upstream
// Standard CAN frame (11-bit ID, 8B data) → ETH gateway (0xCAFE)
// Verifies frame data written to RAM and BD programmed with READY=1
// =========================================================================
class upstream_basic_gw_seq extends uvm_sequence #(wishbone_transaction);
  `uvm_object_utils(upstream_basic_gw_seq)

  bridge_reg_write_seq wr_seq;
  bridge_reg_read_seq  rd_seq;

  // Expected CAN frame fields (set by test)
  bit [28:0] can_id  = 29'h1AB;
  bit [3:0]  dlc     = 4'd8;
  bit        eff     = 1'b0;
  bit        rtr     = 1'b0;
  bit [7:0]  data[8] = '{8'hDE, 8'hAD, 8'hBE, 8'hEF,
                          8'hCA, 8'hFE, 8'h01, 8'h02};

  // Outputs: read back from RAM for checking
  bit [31:0] ram_words[16];
  bit [31:0] bd_status;
  bit [31:0] bd_ptr;
  bit        frame_ok;

  function new(string name = "upstream_basic_gw_seq");
    super.new(name);
  endfunction

  virtual task body();
    `uvm_info(get_type_name(), "UP-01: Starting basic gateway upstream test...", UVM_MEDIUM)

    wr_seq = bridge_reg_write_seq::type_id::create("wr_seq");
    rd_seq = bridge_reg_read_seq::type_id::create("rd_seq");

    // Step 1: Configure bridge — gateway mode, enabled, filter disabled
    wr_seq.addr = {24'h0, `REG_BRIDGE_CTRL};
    wr_seq.data = 32'h0000_0003;  // enable=1, mode=gateway(01)
    wr_seq.start(m_sequencer);

    wr_seq.addr = {24'h0, `REG_FILTER_CTRL};
    wr_seq.data = 32'h0000_0000;  // filter disabled
    wr_seq.start(m_sequencer);

    `uvm_info(get_type_name(), "Bridge configured: gateway mode, filter disabled.", UVM_MEDIUM)

    // NOTE: CAN frame loading + IRQ assertion + ETH TX IRQ happens in the test.
    // This sequence only handles the host-side config and verification.

    `uvm_info(get_type_name(), "UP-01: Gateway config complete. Ready for frame injection.", UVM_MEDIUM)
  endtask
endclass


// =========================================================================
// UP-02: Extended Frame Format (EFF)
// CAN frame with 29-bit extended ID, verify EFF flag in bridge header
// =========================================================================
class upstream_eff_seq extends uvm_sequence #(wishbone_transaction);
  `uvm_object_utils(upstream_eff_seq)

  bridge_reg_write_seq wr_seq;

  function new(string name = "upstream_eff_seq");
    super.new(name);
  endfunction

  virtual task body();
    `uvm_info(get_type_name(), "UP-02: Starting EFF upstream test...", UVM_MEDIUM)

    wr_seq = bridge_reg_write_seq::type_id::create("wr_seq");

    // Configure bridge — gateway mode, enabled, filter disabled
    wr_seq.addr = {24'h0, `REG_BRIDGE_CTRL};
    wr_seq.data = 32'h0000_0003;
    wr_seq.start(m_sequencer);

    wr_seq.addr = {24'h0, `REG_FILTER_CTRL};
    wr_seq.data = 32'h0000_0000;
    wr_seq.start(m_sequencer);

    `uvm_info(get_type_name(), "UP-02: Config complete. Ready for EFF frame injection.", UVM_MEDIUM)
  endtask
endclass


// =========================================================================
// UP-03: DLC Sweep
// Send CAN frames with DLC 0 through 8, verify correct length and padding
// =========================================================================
class upstream_dlc_sweep_seq extends uvm_sequence #(wishbone_transaction);
  `uvm_object_utils(upstream_dlc_sweep_seq)

  bridge_reg_write_seq wr_seq;
  bridge_reg_read_seq  rd_seq;

  function new(string name = "upstream_dlc_sweep_seq");
    super.new(name);
  endfunction

  virtual task body();
    `uvm_info(get_type_name(), "UP-03: Starting DLC sweep upstream test...", UVM_MEDIUM)

    wr_seq = bridge_reg_write_seq::type_id::create("wr_seq");
    rd_seq = bridge_reg_read_seq::type_id::create("rd_seq");

    // Configure bridge — gateway mode, enabled, filter disabled
    wr_seq.addr = {24'h0, `REG_BRIDGE_CTRL};
    wr_seq.data = 32'h0000_0003;
    wr_seq.start(m_sequencer);

    wr_seq.addr = {24'h0, `REG_FILTER_CTRL};
    wr_seq.data = 32'h0000_0000;
    wr_seq.start(m_sequencer);

    `uvm_info(get_type_name(), "UP-03: Config complete. Ready for DLC sweep.", UVM_MEDIUM)
  endtask
endclass


// =========================================================================
// UP-04: Tunnel Mode Upstream
// CAN frame in tunnel mode — verify EtherType=0xCABE, tunnel header
// with sequence number and timestamp, and seq auto-increment
// =========================================================================
class upstream_tunnel_seq extends uvm_sequence #(wishbone_transaction);
  `uvm_object_utils(upstream_tunnel_seq)

  bridge_reg_write_seq wr_seq;
  bridge_reg_read_seq  rd_seq;

  function new(string name = "upstream_tunnel_seq");
    super.new(name);
  endfunction

  virtual task body();
    `uvm_info(get_type_name(), "UP-04: Starting tunnel mode upstream test...", UVM_MEDIUM)

    wr_seq = bridge_reg_write_seq::type_id::create("wr_seq");
    rd_seq = bridge_reg_read_seq::type_id::create("rd_seq");

    // Configure bridge — tunnel mode, enabled, filter disabled
    wr_seq.addr = {24'h0, `REG_BRIDGE_CTRL};
    wr_seq.data = 32'h0000_0005;  // enable=1, mode=tunnel(10)
    wr_seq.start(m_sequencer);

    wr_seq.addr = {24'h0, `REG_FILTER_CTRL};
    wr_seq.data = 32'h0000_0000;
    wr_seq.start(m_sequencer);

    `uvm_info(get_type_name(), "UP-04: Config complete (tunnel mode). Ready for frame injection.", UVM_MEDIUM)
  endtask
endclass


// =========================================================================
// UP-05: Filter Drop (upstream)
// Send a CAN frame that filter rejects. Verify FSM path:
// IDLE → READ_CAN → FILTER → IDLE (no ENCAP, no RAM write, no BD)
// =========================================================================
class upstream_filter_drop_seq extends uvm_sequence #(wishbone_transaction);
  `uvm_object_utils(upstream_filter_drop_seq)

  bridge_reg_write_seq wr_seq;
  bridge_reg_read_seq  rd_seq;

  // CAN IDs
  bit [28:0] accept_id = 29'h100;   // In filter table → pass
  bit [28:0] drop_id   = 29'h7FF;   // NOT in table → drop

  function new(string name = "upstream_filter_drop_seq");
    super.new(name);
  endfunction

  virtual task body();
    `uvm_info(get_type_name(), "UP-05: Starting filter drop upstream test...", UVM_MEDIUM)

    wr_seq = bridge_reg_write_seq::type_id::create("wr_seq");
    rd_seq = bridge_reg_read_seq::type_id::create("rd_seq");

    // Configure bridge — gateway mode, enabled
    wr_seq.addr = {24'h0, `REG_BRIDGE_CTRL};
    wr_seq.data = 32'h0000_0003;
    wr_seq.start(m_sequencer);

    // Write accept_id into filter table entry 0
    wr_seq.addr = {24'h0, `REG_FILTER_TBL_BASE};
    wr_seq.data = {3'h0, accept_id};
    wr_seq.start(m_sequencer);

    // Clear remaining filter entries
    for (int i = 1; i < 16; i++) begin
      wr_seq.addr = {24'h0, `REG_FILTER_TBL_BASE + i * 4};
      wr_seq.data = 32'h0;
      wr_seq.start(m_sequencer);
    end

    // Enable filter in accept-list mode
    wr_seq.addr = {24'h0, `REG_FILTER_CTRL};
    wr_seq.data = 32'h0000_0001;  // filter_en=1, filter_mode=0 (accept)
    wr_seq.start(m_sequencer);

    `uvm_info(get_type_name(), "UP-05: Filter config complete. Ready for drop-frame injection.", UVM_MEDIUM)
  endtask
endclass
