// bridge_downstream_seq.sv — Downstream test sequences (ETH → CAN)
// Covers tests: DN-01, DN-02, DN-03, DN-04


// =========================================================================
// Helper: Build a gateway Ethernet frame in memory for downstream testing
// Constructs the exact same layout that upstream ENCAP produces.
// Word layout:
//   [0] dst_mac[47:16]
//   [1] {dst_mac[15:0], src_mac[47:32]}
//   [2] src_mac[31:0]
//   [3] {EtherType, magic_hi, magic_lo}
//   [4] {version, can_id[28:5]}
//   [5] {can_id[4:0], 3'b0, 4'b0, dlc[3:0], 6'b0, rtr, eff, data[0]}
//   [6] data[1..4]   (gateway) or {tunnel_seq, timestamp} (tunnel)
//   [7] {data[5..7], 0x00}  (gateway) or data[1..4] (tunnel)
//   [8..15] zero padding
// =========================================================================
class downstream_frame_builder extends uvm_object;
  `uvm_object_utils(downstream_frame_builder)

  function new(string name = "downstream_frame_builder");
    super.new(name);
  endfunction

  // Build a valid gateway frame and load it into mem_cfg memory
  static function void build_gateway_frame(
    mem_wb_agent_config mem_cfg,
    bit [31:0] frame_base,     // RAM address where frame data starts
    bit [28:0] can_id,
    bit [3:0]  dlc,
    bit        eff,
    bit        rtr,
    bit [7:0]  data[8]
  );
    bit [31:0] word_addr;
    bit [31:0] dst_hi, dst_lo, src_hi, src_lo;
    word_addr = frame_base >> 2;
    dst_hi = `DEFAULT_DST_MAC_HI;
    dst_lo = `DEFAULT_DST_MAC_LO;
    src_hi = `DEFAULT_SRC_MAC_HI;
    src_lo = `DEFAULT_SRC_MAC_LO;

    // ETH header
    mem_cfg.memory[word_addr + 0]  = dst_hi;
    mem_cfg.memory[word_addr + 1]  = {dst_lo[15:0], src_hi[31:16]};
    mem_cfg.memory[word_addr + 2]  = {src_hi[15:0], src_lo[15:0]};
    // EtherType + magic
    mem_cfg.memory[word_addr + 3]  = {`ETHERTYPE_GATEWAY, `BRIDGE_MAGIC_HI, `BRIDGE_MAGIC_LO};
    // Version + CAN ID upper
    mem_cfg.memory[word_addr + 4]  = {`BRIDGE_VERSION, can_id[28:5]};
    // CAN ID lower + DLC + flags + data[0]
    mem_cfg.memory[word_addr + 5]  = {can_id[4:0], 3'b0, 4'b0, dlc, 6'b0, rtr, eff, data[0]};
    // Data bytes
    mem_cfg.memory[word_addr + 6]  = {data[1], data[2], data[3], data[4]};
    mem_cfg.memory[word_addr + 7]  = {data[5], data[6], data[7], 8'h00};
    // Zero padding
    for (int i = 8; i < 16; i++)
      mem_cfg.memory[word_addr + i] = 32'h0;
  endfunction

  // Build a valid tunnel frame (EtherType=0xCABE)
  static function void build_tunnel_frame(
    mem_wb_agent_config mem_cfg,
    bit [31:0] frame_base,
    bit [28:0] can_id,
    bit [3:0]  dlc,
    bit        eff,
    bit        rtr,
    bit [7:0]  data[8]
  );
    bit [31:0] word_addr;
    bit [31:0] dst_hi, dst_lo, src_hi, src_lo;
    word_addr = frame_base >> 2;
    dst_hi = `DEFAULT_DST_MAC_HI;
    dst_lo = `DEFAULT_DST_MAC_LO;
    src_hi = `DEFAULT_SRC_MAC_HI;
    src_lo = `DEFAULT_SRC_MAC_LO;

    mem_cfg.memory[word_addr + 0]  = dst_hi;
    mem_cfg.memory[word_addr + 1]  = {dst_lo[15:0], src_hi[31:16]};
    mem_cfg.memory[word_addr + 2]  = {src_hi[15:0], src_lo[15:0]};
    // Tunnel EtherType
    mem_cfg.memory[word_addr + 3]  = {`ETHERTYPE_TUNNEL, `BRIDGE_MAGIC_HI, `BRIDGE_MAGIC_LO};
    mem_cfg.memory[word_addr + 4]  = {`BRIDGE_VERSION, can_id[28:5]};
    mem_cfg.memory[word_addr + 5]  = {can_id[4:0], 3'b0, 4'b0, dlc, 6'b0, rtr, eff, data[0]};
    // Word 6: tunnel header (seq# + timestamp)
    mem_cfg.memory[word_addr + 6]  = 32'h0001_0000;  // seq=1, ts=0
    // Word 7: data[1..4]
    mem_cfg.memory[word_addr + 7]  = {data[1], data[2], data[3], data[4]};
    // Word 8: {data[5..7], 0x00}
    mem_cfg.memory[word_addr + 8]  = {data[5], data[6], data[7], 8'h00};
    for (int i = 9; i < 16; i++)
      mem_cfg.memory[word_addr + i] = 32'h0;
  endfunction

  // Build a frame with a custom EtherType (for error injection)
  static function void build_custom_ethertype_frame(
    mem_wb_agent_config mem_cfg,
    bit [31:0] frame_base,
    bit [15:0] ethertype
  );
    bit [31:0] word_addr;
    bit [31:0] dst_hi, dst_lo, src_hi, src_lo;
    word_addr = frame_base >> 2;
    dst_hi = `DEFAULT_DST_MAC_HI;
    dst_lo = `DEFAULT_DST_MAC_LO;
    src_hi = `DEFAULT_SRC_MAC_HI;
    src_lo = `DEFAULT_SRC_MAC_LO;

    mem_cfg.memory[word_addr + 0]  = dst_hi;
    mem_cfg.memory[word_addr + 1]  = {dst_lo[15:0], src_hi[31:16]};
    mem_cfg.memory[word_addr + 2]  = {src_hi[15:0], src_lo[15:0]};
    // Wrong EtherType but correct magic
    mem_cfg.memory[word_addr + 3]  = {ethertype, `BRIDGE_MAGIC_HI, `BRIDGE_MAGIC_LO};
    mem_cfg.memory[word_addr + 4]  = {`BRIDGE_VERSION, 24'h0};
    mem_cfg.memory[word_addr + 5]  = 32'h0;
    for (int i = 6; i < 16; i++)
      mem_cfg.memory[word_addr + i] = 32'h0;
  endfunction

  // Build a frame with an invalid DLC (> 8)
  static function void build_bad_dlc_frame(
    mem_wb_agent_config mem_cfg,
    bit [31:0] frame_base,
    bit [3:0]  bad_dlc
  );
    bit [31:0] word_addr;
    bit [31:0] dst_hi, dst_lo, src_hi, src_lo;
    word_addr = frame_base >> 2;
    dst_hi = `DEFAULT_DST_MAC_HI;
    dst_lo = `DEFAULT_DST_MAC_LO;
    src_hi = `DEFAULT_SRC_MAC_HI;
    src_lo = `DEFAULT_SRC_MAC_LO;

    mem_cfg.memory[word_addr + 0]  = dst_hi;
    mem_cfg.memory[word_addr + 1]  = {dst_lo[15:0], src_hi[31:16]};
    mem_cfg.memory[word_addr + 2]  = {src_hi[15:0], src_lo[15:0]};
    mem_cfg.memory[word_addr + 3]  = {`ETHERTYPE_GATEWAY, `BRIDGE_MAGIC_HI, `BRIDGE_MAGIC_LO};
    mem_cfg.memory[word_addr + 4]  = {`BRIDGE_VERSION, 24'h0};
    // DLC field at bits [19:16] of word5
    mem_cfg.memory[word_addr + 5]  = {5'b0, 3'b0, 4'b0, bad_dlc, 16'h0};
    for (int i = 6; i < 16; i++)
      mem_cfg.memory[word_addr + i] = 32'h0;
  endfunction

  // Build a frame with correct EtherType but custom (wrong) magic bytes
  static function void build_custom_magic_frame(
    mem_wb_agent_config mem_cfg,
    bit [31:0] frame_base,
    bit [15:0] ethertype,
    bit  [7:0] magic_hi,
    bit  [7:0] magic_lo
  );
    bit [31:0] word_addr;
    bit [31:0] dst_hi, dst_lo, src_hi, src_lo;
    word_addr = frame_base >> 2;
    dst_hi = `DEFAULT_DST_MAC_HI;
    dst_lo = `DEFAULT_DST_MAC_LO;
    src_hi = `DEFAULT_SRC_MAC_HI;
    src_lo = `DEFAULT_SRC_MAC_LO;

    mem_cfg.memory[word_addr + 0]  = dst_hi;
    mem_cfg.memory[word_addr + 1]  = {dst_lo[15:0], src_hi[31:16]};
    mem_cfg.memory[word_addr + 2]  = {src_hi[15:0], src_lo[15:0]};
    // Correct EtherType but wrong magic bytes
    mem_cfg.memory[word_addr + 3]  = {ethertype, magic_hi, magic_lo};
    mem_cfg.memory[word_addr + 4]  = {`BRIDGE_VERSION, 24'h0};
    mem_cfg.memory[word_addr + 5]  = 32'h0;
    for (int i = 6; i < 16; i++)
      mem_cfg.memory[word_addr + i] = 32'h0;
  endfunction
endclass


// =========================================================================
// DN-01: Basic Gateway Downstream Sequence
// Configure bridge and set up memory with valid gateway frame
// =========================================================================
class downstream_basic_gw_seq extends uvm_sequence #(wishbone_transaction);
  `uvm_object_utils(downstream_basic_gw_seq)

  bridge_reg_write_seq wr_seq;

  function new(string name = "downstream_basic_gw_seq");
    super.new(name);
  endfunction

  virtual task body();
    `uvm_info(get_type_name(), "DN-01: Configuring bridge for downstream gateway test...", UVM_MEDIUM)

    wr_seq = bridge_reg_write_seq::type_id::create("wr_seq");

    // Enable bridge, gateway mode, filter disabled
    wr_seq.addr = {24'h0, `REG_BRIDGE_CTRL};
    wr_seq.data = 32'h0000_0003;
    wr_seq.start(m_sequencer);

    wr_seq.addr = {24'h0, `REG_FILTER_CTRL};
    wr_seq.data = 32'h0000_0000;
    wr_seq.start(m_sequencer);

    `uvm_info(get_type_name(), "DN-01: Config complete.", UVM_MEDIUM)
  endtask
endclass


// =========================================================================
// DN-02: Bad EtherType Downstream Sequence
// =========================================================================
class downstream_bad_ethertype_seq extends uvm_sequence #(wishbone_transaction);
  `uvm_object_utils(downstream_bad_ethertype_seq)

  bridge_reg_write_seq wr_seq;

  function new(string name = "downstream_bad_ethertype_seq");
    super.new(name);
  endfunction

  virtual task body();
    `uvm_info(get_type_name(), "DN-02: Configuring bridge for bad EtherType test...", UVM_MEDIUM)

    wr_seq = bridge_reg_write_seq::type_id::create("wr_seq");

    wr_seq.addr = {24'h0, `REG_BRIDGE_CTRL};
    wr_seq.data = 32'h0000_0003;
    wr_seq.start(m_sequencer);

    wr_seq.addr = {24'h0, `REG_FILTER_CTRL};
    wr_seq.data = 32'h0000_0000;
    wr_seq.start(m_sequencer);

    `uvm_info(get_type_name(), "DN-02: Config complete.", UVM_MEDIUM)
  endtask
endclass


// =========================================================================
// DN-03: Bad DLC Downstream Sequence
// =========================================================================
class downstream_bad_dlc_seq extends uvm_sequence #(wishbone_transaction);
  `uvm_object_utils(downstream_bad_dlc_seq)

  bridge_reg_write_seq wr_seq;

  function new(string name = "downstream_bad_dlc_seq");
    super.new(name);
  endfunction

  virtual task body();
    `uvm_info(get_type_name(), "DN-03: Configuring bridge for bad DLC test...", UVM_MEDIUM)

    wr_seq = bridge_reg_write_seq::type_id::create("wr_seq");

    wr_seq.addr = {24'h0, `REG_BRIDGE_CTRL};
    wr_seq.data = 32'h0000_0003;
    wr_seq.start(m_sequencer);

    wr_seq.addr = {24'h0, `REG_FILTER_CTRL};
    wr_seq.data = 32'h0000_0000;
    wr_seq.start(m_sequencer);

    `uvm_info(get_type_name(), "DN-03: Config complete.", UVM_MEDIUM)
  endtask
endclass


// =========================================================================
// DN-04: Backpressure Downstream Sequence
// =========================================================================
class downstream_backpressure_seq extends uvm_sequence #(wishbone_transaction);
  `uvm_object_utils(downstream_backpressure_seq)

  bridge_reg_write_seq wr_seq;

  function new(string name = "downstream_backpressure_seq");
    super.new(name);
  endfunction

  virtual task body();
    `uvm_info(get_type_name(), "DN-04: Configuring bridge for backpressure test...", UVM_MEDIUM)

    wr_seq = bridge_reg_write_seq::type_id::create("wr_seq");

    wr_seq.addr = {24'h0, `REG_BRIDGE_CTRL};
    wr_seq.data = 32'h0000_0003;
    wr_seq.start(m_sequencer);

    wr_seq.addr = {24'h0, `REG_FILTER_CTRL};
    wr_seq.data = 32'h0000_0000;
    wr_seq.start(m_sequencer);

    `uvm_info(get_type_name(), "DN-04: Config complete.", UVM_MEDIUM)
  endtask
endclass


// =========================================================================
// DN-05: Bad Magic Byte Downstream Sequence
// =========================================================================
class downstream_bad_magic_seq extends uvm_sequence #(wishbone_transaction);
  `uvm_object_utils(downstream_bad_magic_seq)

  bridge_reg_write_seq wr_seq;

  function new(string name = "downstream_bad_magic_seq");
    super.new(name);
  endfunction

  virtual task body();
    `uvm_info(get_type_name(), "DN-05: Configuring bridge for bad magic byte test...", UVM_MEDIUM)

    wr_seq = bridge_reg_write_seq::type_id::create("wr_seq");

    wr_seq.addr = {24'h0, `REG_BRIDGE_CTRL};
    wr_seq.data = 32'h0000_0003;
    wr_seq.start(m_sequencer);

    wr_seq.addr = {24'h0, `REG_FILTER_CTRL};
    wr_seq.data = 32'h0000_0000;
    wr_seq.start(m_sequencer);

    `uvm_info(get_type_name(), "DN-05: Config complete.", UVM_MEDIUM)
  endtask
endclass


// =========================================================================
// RST-01: Mid-Transaction Reset Sequence
// =========================================================================
class mid_transaction_reset_seq extends uvm_sequence #(wishbone_transaction);
  `uvm_object_utils(mid_transaction_reset_seq)

  bridge_reg_write_seq wr_seq;

  function new(string name = "mid_transaction_reset_seq");
    super.new(name);
  endfunction

  virtual task body();
    `uvm_info(get_type_name(), "RST-01: Configuring bridge for mid-transaction reset test...", UVM_MEDIUM)

    wr_seq = bridge_reg_write_seq::type_id::create("wr_seq");

    // Enable bridge, gateway mode
    wr_seq.addr = {24'h0, `REG_BRIDGE_CTRL};
    wr_seq.data = 32'h0000_0003;
    wr_seq.start(m_sequencer);

    // Filter disabled
    wr_seq.addr = {24'h0, `REG_FILTER_CTRL};
    wr_seq.data = 32'h0000_0000;
    wr_seq.start(m_sequencer);

    `uvm_info(get_type_name(), "RST-01: Config complete.", UVM_MEDIUM)
  endtask
endclass


// =========================================================================
// DN-06: Downstream Tunnel Mode Sequence
// =========================================================================
class downstream_tunnel_seq extends uvm_sequence #(wishbone_transaction);
  `uvm_object_utils(downstream_tunnel_seq)

  bridge_reg_write_seq wr_seq;

  function new(string name = "downstream_tunnel_seq");
    super.new(name);
  endfunction

  virtual task body();
    `uvm_info(get_type_name(), "DN-06: Configuring bridge for downstream tunnel test...", UVM_MEDIUM)

    wr_seq = bridge_reg_write_seq::type_id::create("wr_seq");

    // Enable bridge, TUNNEL mode (mode=10 → bit2=1, bit1=0, bit0=1 enable)
    wr_seq.addr = {24'h0, `REG_BRIDGE_CTRL};
    wr_seq.data = 32'h0000_0005;  // enable=1, mode=tunnel
    wr_seq.start(m_sequencer);

    // Filter disabled
    wr_seq.addr = {24'h0, `REG_FILTER_CTRL};
    wr_seq.data = 32'h0000_0000;
    wr_seq.start(m_sequencer);

    `uvm_info(get_type_name(), "DN-06: Config complete.", UVM_MEDIUM)
  endtask
endclass
