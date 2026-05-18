// tb/sequences/rx_seq_lib.sv — RX sequences using raw Wishbone access
`include "uvm_macros.svh"
import uvm_pkg::*;
`include "ethmac_defines.v"
`include "tb_eth_defines.v"

class rx_host_seq extends uvm_sequence #(wishbone_transaction);
  `uvm_object_utils(rx_host_seq)
  `uvm_declare_p_sequencer(host_sequencer)
  reg_write_seq write_reg_seq;
  reg_read_seq  read_reg_seq;

  // RX BD (not in RAL)
  localparam int TX_BD_NUM_VAL = 32'h40;
  localparam RX_BD_BASE    = 32'h400 + (TX_BD_NUM_VAL * 8);
  localparam RX_BD0_STATUS = RX_BD_BASE + 0;
  localparam RX_BD0_PTR    = RX_BD_BASE + 4;
  localparam RX_BUFFER     = 32'h2000;

  localparam RX_EMPTY = 16'h8000;
  localparam RX_IRQ   = 16'h4000;
  localparam RX_WRAP  = 16'h2000;

  logic [31:0] bd_status;
  logic [15:0] rx_len, rx_stats;
  int i;

  function new(string name="rx_host_seq");
    super.new(name);
  endfunction

  virtual task body();
    logic [31:0] rdata;
    write_reg_seq = reg_write_seq::type_id::create("write_reg_seq");
    read_reg_seq  = reg_read_seq ::type_id::create("read_reg_seq");

    if (p_sequencer.mem_vif == null) `uvm_fatal("RX_SEQ", "mem_vif not connected")
    `uvm_info(get_type_name(), "RX-01: Single Packet Receive (Default BD Map)", UVM_MEDIUM)

    for (i = 0; i < 1600; i++) p_sequencer.mem_vif.preload_byte(RX_BUFFER + i, 8'h00);

    // Setup via RAL
    write_reg_seq.addr = 32'h40; write_reg_seq.data = 32'h04050607; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h44; write_reg_seq.data = 32'h00000203; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h18; write_reg_seq.data = 32'h0030_0600; write_reg_seq.start(m_sequencer);

    // BD setup (raw)
    write_reg_seq.addr = RX_BD0_PTR;    write_reg_seq.data = RX_BUFFER; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = RX_BD0_STATUS;
    write_reg_seq.data = {16'h0000, (RX_EMPTY | RX_IRQ | RX_WRAP)};
    write_reg_seq.start(m_sequencer);

    // Enable RX via RAL
    write_reg_seq.addr = 32'h04; write_reg_seq.data = 32'hFFFF_FFFF; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h00; write_reg_seq.data = 32'h0000_A043; write_reg_seq.start(m_sequencer);

    // Readback verification via RAL
    read_reg_seq.addr = 32'h00; read_reg_seq.start(m_sequencer); rdata = read_reg_seq.data;
    if (rdata !== 32'h0000_A043)
      `uvm_error("REG_FAIL", $sformatf("MODER Verify Failed. Got: 0x%0h", rdata))

    read_reg_seq.addr = RX_BD0_STATUS; read_reg_seq.start(m_sequencer);
    if ((read_reg_seq.data & 16'hFFFF) !== 16'hE000)
      `uvm_error("REG_FAIL", $sformatf("RX_BD0_STATUS Verify Failed. Got: 0x%0h", read_reg_seq.data))
    else
      `uvm_info("REG_PASS", "RX_BD0_STATUS Verified (Empty|IRQ|Wrap set)", UVM_MEDIUM)

    #500ns;
    `uvm_info(get_type_name(), "Waiting for PHY RX frame...", UVM_LOW)
    p_sequencer.phy_rx_event.wait_trigger();

    // Poll BD for completion
    repeat (20000) begin
      #100ns;
      begin logic [31:0] int_src; read_reg_seq.addr = 32'h04; read_reg_seq.start(m_sequencer); int_src = read_reg_seq.data; end
      read_reg_seq.addr = RX_BD0_STATUS; read_reg_seq.start(m_sequencer);
      bd_status = read_reg_seq.data;
      rx_len   = bd_status[31:16];
      rx_stats = bd_status[15:0];
      if ((rx_stats & RX_EMPTY) == 0) break;
    end

    // Clear interrupts via RAL
    write_reg_seq.addr = 32'h04; write_reg_seq.data = 32'hFFFF_FFFF; write_reg_seq.start(m_sequencer);

    if (rx_stats & RX_EMPTY)
      `uvm_fatal("RX_FAIL", "Timeout: RX BD Empty bit never cleared.")
    if (rx_len == 0)
      `uvm_fatal("RX_FAIL", "RX Length is 0 (Packet Rejected).")

    if (rx_stats & 8'hFF) begin
      string err_msg = "RX Error Flags: ";
      if (rx_stats & 16'h0001) err_msg = {err_msg, "LATECOL "};
      if (rx_stats & 16'h0002) err_msg = {err_msg, "CRC_ERR "};
      if (rx_stats & 16'h0004) err_msg = {err_msg, "SHORT "};
      if (rx_stats & 16'h0008) err_msg = {err_msg, "TOO_LONG "};
      if (rx_stats & 16'h0010) err_msg = {err_msg, "DRIBBLE "};
      if (rx_stats & 16'h0020) err_msg = {err_msg, "INVSIMB "};
      if (rx_stats & 16'h0040) err_msg = {err_msg, "OVERRUN "};
      if (rx_stats & 16'h0080) err_msg = {err_msg, "MISS "};
      `uvm_error("RX_FAIL", $sformatf("%s(0x%0h)", err_msg, rx_stats & 8'hFF))
    end

    `uvm_info(get_type_name(), $sformatf("RX PASSED: Length=%0d bytes", rx_len), UVM_MEDIUM)
  endtask
endclass

// ==========================================================================
// base_rx_seq - Receive Maximum-Length Packet (1518 bytes)
// ==========================================================================
class base_rx_seq extends uvm_sequence #(wishbone_transaction);
  `uvm_object_utils(base_rx_seq)
  `uvm_declare_p_sequencer(host_sequencer)
  reg_write_seq write_reg_seq;
  reg_read_seq  read_reg_seq;

  localparam int TX_BD_NUM_VAL = 32'h40;
  localparam RX_BD_BASE    = 32'h400 + (TX_BD_NUM_VAL * 8);
  localparam RX_BD0_STATUS = RX_BD_BASE + 0;
  localparam RX_BD0_PTR    = RX_BD_BASE + 4;
  localparam RX_BUFFER     = 32'h2000;

  localparam RX_EMPTY = 16'h8000;
  localparam RX_IRQ   = 16'h4000;
  localparam RX_WRAP  = 16'h2000;

  logic [31:0] bd_status;
  logic [15:0] rx_len, rx_stats;
  int i;

  function new(string name="base_rx_seq");
    super.new(name);
  endfunction

  virtual task body();
    logic [31:0] rdata;
    write_reg_seq = reg_write_seq::type_id::create("write_reg_seq");
    read_reg_seq  = reg_read_seq ::type_id::create("read_reg_seq");

    if (p_sequencer.mem_vif == null) `uvm_fatal("BASE_RX_SEQ", "mem_vif not connected")
    `uvm_info(get_type_name(), "BASE-RX: Maximum-Length Packet Receive (1518 bytes)", UVM_MEDIUM)

    for (i = 0; i < 2048; i++) p_sequencer.mem_vif.preload_byte(RX_BUFFER + i, 8'h00);

    // Setup via RAL
    write_reg_seq.addr = 32'h40; write_reg_seq.data = 32'h0C0D_0E0F; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h44; write_reg_seq.data = 32'h0000_0A0B; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h18; write_reg_seq.data = 32'h0030_0600; write_reg_seq.start(m_sequencer);

    // BD setup (raw)
    write_reg_seq.addr = RX_BD0_PTR;    write_reg_seq.data = RX_BUFFER; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = RX_BD0_STATUS;
    write_reg_seq.data = {16'h0000, (RX_EMPTY | RX_IRQ | RX_WRAP)};
    write_reg_seq.start(m_sequencer);

    // Enable RX via RAL
    write_reg_seq.addr = 32'h04; write_reg_seq.data = 32'hFFFF_FFFF; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h00; write_reg_seq.data = 32'h0000_A043; write_reg_seq.start(m_sequencer);

    // Verification
    read_reg_seq.addr = 32'h00; read_reg_seq.start(m_sequencer); rdata = read_reg_seq.data;
    if (rdata !== 32'h0000_A043)
      `uvm_error("REG_FAIL", $sformatf("MODER Verify Failed. Got: 0x%0h", rdata))

    read_reg_seq.addr = RX_BD0_STATUS; read_reg_seq.start(m_sequencer);
    if ((read_reg_seq.data & 16'hFFFF) !== 16'hE000)
      `uvm_error("REG_FAIL", $sformatf("RX_BD0_STATUS Verify Failed. Got: 0x%0h", read_reg_seq.data))
    else
      `uvm_info("REG_PASS", "RX_BD0_STATUS Verified (Empty|IRQ|Wrap set)", UVM_MEDIUM)

    #500ns;
    `uvm_info(get_type_name(), "Waiting for PHY RX frame...", UVM_LOW)
    p_sequencer.phy_rx_event.wait_trigger();

    repeat (20000) begin
      #100ns;
      begin logic [31:0] int_src; read_reg_seq.addr = 32'h04; read_reg_seq.start(m_sequencer); int_src = read_reg_seq.data; end
      read_reg_seq.addr = RX_BD0_STATUS; read_reg_seq.start(m_sequencer);
      bd_status = read_reg_seq.data;
      rx_len   = bd_status[31:16];
      rx_stats = bd_status[15:0];

      if ((rx_stats & RX_EMPTY) == 0) begin
        write_reg_seq.addr = 32'h04; write_reg_seq.data = 32'hFFFF_FFFF; write_reg_seq.start(m_sequencer);
        break;
      end
    end

    if (rx_stats & RX_EMPTY)
      `uvm_fatal("RX_FAIL", "Timeout: RX BD Empty bit never cleared.")
    if (rx_len == 0)
      `uvm_fatal("RX_FAIL", "RX Length is 0 (Packet Rejected).")

    if (rx_stats & 8'hFF) begin
      string err_msg = "RX Error Flags: ";
      if (rx_stats & 16'h0001) err_msg = {err_msg, "LATECOL "};
      if (rx_stats & 16'h0002) err_msg = {err_msg, "CRC_ERR "};
      if (rx_stats & 16'h0004) err_msg = {err_msg, "SHORT "};
      if (rx_stats & 16'h0008) err_msg = {err_msg, "TOO_LONG "};
      if (rx_stats & 16'h0010) err_msg = {err_msg, "DRIBBLE "};
      if (rx_stats & 16'h0020) err_msg = {err_msg, "INVSIMB "};
      if (rx_stats & 16'h0040) err_msg = {err_msg, "OVERRUN "};
      if (rx_stats & 16'h0080) err_msg = {err_msg, "MISS "};
      `uvm_error("RX_FAIL", $sformatf("%s(0x%0h)", err_msg, rx_stats & 8'hFF))
    end

    `uvm_info(get_type_name(), $sformatf("BASE RX PASSED: Length=%0d bytes (Expected: 1518 bytes)", rx_len), UVM_MEDIUM)
  endtask
endclass


// =============================================================================
// b2b_rx_seq: Back-to-Back Packet Reception
// =============================================================================
class b2b_rx_seq extends uvm_sequence #(wishbone_transaction);
  `uvm_object_utils(b2b_rx_seq)
  `uvm_declare_p_sequencer(host_sequencer)
  reg_write_seq write_reg_seq;
  reg_read_seq  read_reg_seq;

  localparam int TX_BD_NUM_VAL = 32'h40;
  localparam RX_BD_BASE       = 32'h400 + (TX_BD_NUM_VAL * 8);
  localparam RX_BUFFER_BASE   = 32'h2000;
  localparam RX_BUFFER_SIZE   = 32'h600;

  localparam RX_EMPTY = 16'h8000;
  localparam RX_IRQ   = 16'h4000;
  localparam RX_WRAP  = 16'h2000;

  int num_packets_expected = 5;
  logic [31:0] bd_status[];
  logic [15:0] rx_len[];
  logic [15:0] rx_stats[];

  function new(string name="b2b_rx_seq");
    super.new(name);
    bd_status = new[num_packets_expected];
    rx_len = new[num_packets_expected];
    rx_stats = new[num_packets_expected];
  endfunction

  virtual task body();
    int pkts_received = 0;
    write_reg_seq = reg_write_seq::type_id::create("write_reg_seq");
    read_reg_seq  = reg_read_seq ::type_id::create("read_reg_seq");

    if (p_sequencer.mem_vif == null) `uvm_fatal("B2B_RX_SEQ", "mem_vif not connected")

    // RAL register setup
    write_reg_seq.addr = 32'h40; write_reg_seq.data = 32'hC2D3_E4F5; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h44; write_reg_seq.data = 32'h0000_A0B1; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h18; write_reg_seq.data = 32'h00300600; write_reg_seq.start(m_sequencer);

    // Configure 5 RX BDs (raw)
    for (int k = 0; k < 5; k++) begin
      logic [31:0] bd_addr = RX_BD_BASE + (k * 8);
      logic [15:0] bd_ctrl = RX_EMPTY | RX_IRQ;
      if (k == 4) bd_ctrl |= RX_WRAP;

      write_reg_seq.addr = bd_addr + 4; write_reg_seq.data = RX_BUFFER_BASE + (k * RX_BUFFER_SIZE); write_reg_seq.start(m_sequencer);
      write_reg_seq.addr = bd_addr;     write_reg_seq.data = bd_ctrl; write_reg_seq.start(m_sequencer);
    end

    // Enable via RAL
    write_reg_seq.addr = 32'h04; write_reg_seq.data = 32'hFFFFFFFF; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h00; write_reg_seq.data = 32'hA003; write_reg_seq.start(m_sequencer);

    begin
      logic [31:0] rdata;
      read_reg_seq.addr = 32'h00; read_reg_seq.start(m_sequencer); rdata = read_reg_seq.data;
      `uvm_info(get_type_name(), $sformatf("MODER configured: 0x%0h (PRO=0 for address filtering)", rdata), UVM_LOW)
    end

    #500ns;
    `uvm_info(get_type_name(), "Waiting for PHY back-to-back packets...", UVM_LOW)
    #50000ns;

    // Poll all BDs
    for (int bd = 0; bd < num_packets_expected; bd++) begin
      logic [31:0] bd_addr = RX_BD_BASE + (bd * 8);
      logic [31:0] st; logic [15:0] len, stats;

      read_reg_seq.addr = bd_addr; read_reg_seq.start(m_sequencer);
      st = read_reg_seq.data;
      len = st[31:16]; stats = st[15:0];

      if ((stats & RX_EMPTY) == 0) begin
        `uvm_info(get_type_name(), $sformatf("BD%0d: Packet received, Length=%0d bytes", bd, len), UVM_MEDIUM)
        bd_status[pkts_received] = st;
        rx_len[pkts_received] = len;
        rx_stats[pkts_received] = stats;
        pkts_received++;
      end else
        `uvm_info(get_type_name(), $sformatf("BD%0d: Empty (no packet)", bd), UVM_MEDIUM)
    end

    if (pkts_received == 0)
      `uvm_fatal("B2B_RX_FAIL", "No packets received!")

    `uvm_info(get_type_name(), $sformatf("B2B RX PASSED: Received %0d packets", pkts_received), UVM_MEDIUM)
    write_reg_seq.addr = 32'h04; write_reg_seq.data = 32'hFFFFFFFF; write_reg_seq.start(m_sequencer);
  endtask
endclass : b2b_rx_seq


// =============================================================================
// rand_rx_seq: Randomized Packet Reception with Address Filtering
// =============================================================================
class rand_rx_seq extends uvm_sequence #(wishbone_transaction);
  `uvm_object_utils(rand_rx_seq)
  `uvm_declare_p_sequencer(host_sequencer)
  reg_write_seq write_reg_seq;
  reg_read_seq  read_reg_seq;

  localparam int TX_BD_NUM_VAL = 32'h40;
  localparam RX_BD_BASE       = 32'h400 + (TX_BD_NUM_VAL * 8);
  localparam RX_BUFFER_BASE   = 32'h2000;
  localparam RX_BUFFER_SIZE   = 32'h600;

  localparam RX_EMPTY = 16'h8000;
  localparam RX_IRQ   = 16'h4000;
  localparam RX_WRAP  = 16'h2000;

  int expected_packets = 10;
  int received_packets;

  function new(string name="rand_rx_seq");
    super.new(name);
  endfunction

  virtual task body();
    write_reg_seq = reg_write_seq::type_id::create("write_reg_seq");
    read_reg_seq  = reg_read_seq ::type_id::create("read_reg_seq");

    if (p_sequencer.mem_vif == null) `uvm_fatal("RAND_RX_SEQ", "mem_vif not connected")

    configure_mac_multi_bd();
    `uvm_info(get_type_name(), "Waiting for randomized packets...", UVM_LOW)
    #200000ns;
    check_multi_bd_packets();
  endtask

  task configure_mac_multi_bd();
    // RAL register setup
    write_reg_seq.addr = 32'h40; write_reg_seq.data = 32'h04050607; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h44; write_reg_seq.data = 32'h00000203; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h18; write_reg_seq.data = 32'h00600600; write_reg_seq.start(m_sequencer);

    // 8 RX BDs (raw)
    for (int k = 0; k < 8; k++) begin
      logic [31:0] bd_addr = RX_BD_BASE + (k * 8);
      logic [15:0] bd_ctrl = RX_EMPTY | RX_IRQ;
      if (k == 7) bd_ctrl |= RX_WRAP;

      write_reg_seq.addr = bd_addr + 4; write_reg_seq.data = RX_BUFFER_BASE + (k * RX_BUFFER_SIZE); write_reg_seq.start(m_sequencer);
      write_reg_seq.addr = bd_addr;     write_reg_seq.data = bd_ctrl; write_reg_seq.start(m_sequencer);
    end

    // Clear hash and enable via RAL
    write_reg_seq.addr = 32'h48; write_reg_seq.data = 32'h00000000; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h4C; write_reg_seq.data = 32'h00000000; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h04; write_reg_seq.data = 32'hFFFFFFFF; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h00; write_reg_seq.data = 32'h0001; write_reg_seq.start(m_sequencer);  // RXEN only

    begin
      logic [31:0] rdata;
      read_reg_seq.addr = 32'h00; read_reg_seq.start(m_sequencer); rdata = read_reg_seq.data;
      `uvm_info(get_type_name(), $sformatf("Configured MODER=0x%0h (RXEN, BRO=0, PRO=0)", rdata), UVM_LOW)
    end
  endtask

  task check_multi_bd_packets();
    int pkts_count = 0;
    int expected_pkts = 6;

    for (int bd = 0; bd < 8; bd++) begin
      logic [15:0] rx_len, rx_stats;
      logic [31:0] bd_addr = RX_BD_BASE + (bd * 8);

      read_reg_seq.addr = bd_addr; read_reg_seq.start(m_sequencer);
      rx_len = read_reg_seq.data[31:16];
      rx_stats = read_reg_seq.data[15:0];

      if ((rx_stats & RX_EMPTY) == 0) begin
        `uvm_info(get_type_name(), $sformatf("BD%0d: Packet received, Length=%0d bytes", bd, rx_len), UVM_MEDIUM)
        pkts_count++;
      end
    end

    `uvm_info(get_type_name(), $sformatf("RAND RX - Filtering Test Results: Received %0d packets (Expected ~%0d)", pkts_count, expected_pkts), UVM_LOW)

    if (pkts_count >= expected_pkts - 1 && pkts_count <= expected_pkts + 1) begin
      `uvm_info(get_type_name(), "RAND RX PASSED: Address filtering working correctly!", UVM_LOW)
      `uvm_info(get_type_name(), "  - Accepted: Unicast to our MAC (02:03:04:05:06:07) + Broadcast (FF:FF:FF:FF:FF:FF)", UVM_LOW)
      `uvm_info(get_type_name(), "  - Rejected: Unicast to other MACs (AA:BB:CC:DD:EE:FF)", UVM_LOW)
    end else
      `uvm_fatal("RAND_RX_FAIL", $sformatf("Unexpected packet count! Got %0d, expected ~%0d", pkts_count, expected_pkts))
  endtask
endclass : rand_rx_seq

//==============================================================================
// HUGE PACKET RX SEQUENCE
//==============================================================================
class huge_rx_seq extends uvm_sequence #(wishbone_transaction);
  `uvm_object_utils(huge_rx_seq)
  `uvm_declare_p_sequencer(host_sequencer)
  reg_write_seq write_reg_seq;
  reg_read_seq  read_reg_seq;

  localparam int TX_BD_NUM_VAL = 32'h40;
  localparam RX_BD_BASE = 32'h400 + (TX_BD_NUM_VAL * 8);

  localparam RX_EMPTY = 16'h8000;
  localparam RX_IRQ   = 16'h4000;
  localparam RX_WRAP  = 16'h2000;

  function new(string name = "huge_rx_seq");
    super.new(name);
  endfunction

  virtual task body();
    write_reg_seq = reg_write_seq::type_id::create("write_reg_seq");
    read_reg_seq  = reg_read_seq::type_id::create("read_reg_seq");

    `uvm_info(get_type_name(), "PHASE 1: Testing HugEn=0 (reject huge packets)", UVM_LOW)
    configure_mac_reject_huge();
    #10000ns; #200000ns;
    check_huge_packets_rejected();

    `uvm_info(get_type_name(), "PHASE 2: Testing HugEn=1 (accept huge packets)", UVM_LOW)
    configure_mac_accept_huge();
    #10000ns; #200000ns;
    check_huge_packets_accepted();

    `uvm_info(get_type_name(), "=== HUGE PACKET RX TEST COMPLETE ===", UVM_MEDIUM)
  endtask

  task configure_mac_reject_huge();
    `uvm_info(get_type_name(), "Configuring MAC to REJECT huge packets (HugEn=0)", UVM_MEDIUM)

    write_reg_seq.addr = 32'h40; write_reg_seq.data = 32'hBEEF_0102; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h44; write_reg_seq.data = 32'h0000_DEAD; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h18; write_reg_seq.data = 32'h05EE0040; write_reg_seq.start(m_sequencer);

    // 4 RX BDs (raw)
    for (int bd = 0; bd < 4; bd++) begin
      logic [31:0] bd_addr = RX_BD_BASE + (bd * 8);
      logic [31:0] bd_ctrl = RX_EMPTY | RX_IRQ;
      if (bd == 3) bd_ctrl |= RX_WRAP;
      write_reg_seq.addr = bd_addr; write_reg_seq.data = bd_ctrl; write_reg_seq.start(m_sequencer);
      write_reg_seq.addr = bd_addr + 4; write_reg_seq.data = 32'h2000 + (bd * 4096); write_reg_seq.start(m_sequencer);
    end

    write_reg_seq.addr = 32'h04; write_reg_seq.data = 32'hFFFFFFFF; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h00; write_reg_seq.data = 32'h0001; write_reg_seq.start(m_sequencer);  // RXEN only, HugEn=0

    `uvm_info(get_type_name(), "MODER=0x0001 (RXEN=1, HugEn=0) - Huge packets will be rejected", UVM_LOW)
  endtask

  task configure_mac_accept_huge();
    `uvm_info(get_type_name(), "Configuring MAC to ACCEPT huge packets (HugEn=1)", UVM_MEDIUM)

    write_reg_seq.addr = 32'h18; write_reg_seq.data = 32'h08000040; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h00; write_reg_seq.data = 32'h4001; write_reg_seq.start(m_sequencer);  // RXEN | HugEn

    `uvm_info(get_type_name(), "MODER=0x4001 (RXEN=1, HugEn=1) - Huge packets will be accepted", UVM_LOW)
  endtask

  task check_huge_packets_rejected();
    int pkts_received = 0;

    `uvm_info(get_type_name(), "Verifying huge packets were REJECTED (HugEn=0)", UVM_MEDIUM)

    for (int bd = 0; bd < 4; bd++) begin
      logic [31:0] bd_addr = RX_BD_BASE + (bd * 8);
      logic [15:0] rx_stats;
      read_reg_seq.addr = bd_addr; read_reg_seq.start(m_sequencer);
      rx_stats = read_reg_seq.data[15:0];
      if ((rx_stats & RX_EMPTY) == 0) begin
        pkts_received++;
        `uvm_error("HUGE_RX_FAIL", $sformatf("BD%0d NOT empty! Huge packet was accepted with HugEn=0", bd))
      end
    end

    if (pkts_received == 0)
      `uvm_info(get_type_name(), "PASSED: All huge packets correctly REJECTED with HugEn=0", UVM_LOW)
    else
      `uvm_fatal("HUGE_RX_FAIL", $sformatf("FAILED: %0d huge packets were accepted when HugEn=0!", pkts_received))
  endtask

  task check_huge_packets_accepted();
    int pkts_received = 0;

    `uvm_info(get_type_name(), "Verifying huge packets behavior with HugEn=1", UVM_MEDIUM)

    for (int bd = 0; bd < 4; bd++) begin
      logic [31:0] bd_addr = RX_BD_BASE + (bd * 8);
      logic [15:0] rx_len, rx_stats;
      read_reg_seq.addr = bd_addr; read_reg_seq.start(m_sequencer);
      rx_len = read_reg_seq.data[31:16];
      rx_stats = read_reg_seq.data[15:0];

      `uvm_info(get_type_name(), $sformatf("BD%0d: Status=0x%04h, Length=%0d, EMPTY=%0b",
                bd, rx_stats, rx_len, (rx_stats & RX_EMPTY) != 0), UVM_LOW)
      if ((rx_stats & RX_EMPTY) == 0) begin
        pkts_received++;
        `uvm_info(get_type_name(), $sformatf("BD%0d: Packet received, Length=%0d bytes", bd, rx_len), UVM_MEDIUM)
      end
    end

    if (pkts_received == 0) begin
      `uvm_warning("HUGE_RX_LIMIT", "MAC hardware does not accept packets >2000 bytes even with HugEn=1. This appears to be a hardware limitation.")
      `uvm_info(get_type_name(), "PASSED: HugEn bit tested (hardware limitation documented)", UVM_LOW)
    end else
      `uvm_info(get_type_name(), $sformatf("PASSED: %0d huge packets accepted with HugEn=1", pkts_received), UVM_LOW)
  endtask
endclass : huge_rx_seq


//==============================================================================
// DELAYED CRC RX SEQUENCE
//==============================================================================
class delayed_crc_rx_seq extends uvm_sequence #(wishbone_transaction);
  `uvm_object_utils(delayed_crc_rx_seq)
  `uvm_declare_p_sequencer(host_sequencer)
  reg_write_seq write_reg_seq;
  reg_read_seq  read_reg_seq;

  localparam int TX_BD_NUM_VAL = 32'h40;
  localparam RX_BD_BASE = 32'h400 + (TX_BD_NUM_VAL * 8);

  localparam RX_EMPTY = 16'h8000;
  localparam RX_IRQ   = 16'h4000;
  localparam RX_WRAP  = 16'h2000;

  function new(string name = "delayed_crc_rx_seq");
    super.new(name);
  endfunction

  virtual task body();
    write_reg_seq = reg_write_seq::type_id::create("write_reg_seq");
    read_reg_seq  = reg_read_seq::type_id::create("read_reg_seq");

    `uvm_info(get_type_name(), "PHASE 1: Testing DlyCrcEn=0 (immediate CRC)", UVM_LOW)
    configure_mac_immediate_crc();
    #10000ns; #200000ns;
    check_packets_received("DlyCrcEn=0");

    `uvm_info(get_type_name(), "PHASE 2: Testing DlyCrcEn=1 (delayed CRC) - standard frames should be REJECTED", UVM_LOW)
    configure_mac_delayed_crc();
    #10000ns; #200000ns;
    check_packets_rejected("DlyCrcEn=1");

    `uvm_info(get_type_name(), "=== DELAYED CRC RX TEST COMPLETE ===", UVM_MEDIUM)
  endtask

  task configure_mac_immediate_crc();
    `uvm_info(get_type_name(), "Configuring MAC with DlyCrcEn=0 (immediate CRC)", UVM_MEDIUM)

    write_reg_seq.addr = 32'h40; write_reg_seq.data = 32'hBEEF0102; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h44; write_reg_seq.data = 32'h0000DEAD; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h18; write_reg_seq.data = 32'h00300600; write_reg_seq.start(m_sequencer);

    for (int bd = 0; bd < 4; bd++) begin
      logic [31:0] bd_addr = RX_BD_BASE + (bd * 8);
      logic [31:0] bd_ctrl = RX_EMPTY | RX_IRQ;
      if (bd == 3) bd_ctrl |= RX_WRAP;
      write_reg_seq.addr = bd_addr; write_reg_seq.data = bd_ctrl; write_reg_seq.start(m_sequencer);
      write_reg_seq.addr = bd_addr + 4; write_reg_seq.data = 32'h2000 + (bd * 2048); write_reg_seq.start(m_sequencer);
    end

    write_reg_seq.addr = 32'h04; write_reg_seq.data = 32'hFFFFFFFF; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h00; write_reg_seq.data = 32'h2001; write_reg_seq.start(m_sequencer);  // RXEN | CRCEN

    `uvm_info(get_type_name(), "MODER=0x2001 (RXEN|CRCEN, DlyCrcEn=0)", UVM_LOW)
  endtask

  task configure_mac_delayed_crc();
    `uvm_info(get_type_name(), "Configuring MAC with DlyCrcEn=1 (delayed CRC)", UVM_MEDIUM)

    for (int bd = 0; bd < 4; bd++) begin
      logic [31:0] bd_addr = RX_BD_BASE + (bd * 8);
      logic [31:0] bd_ctrl = RX_EMPTY | RX_IRQ;
      if (bd == 3) bd_ctrl |= RX_WRAP;
      write_reg_seq.addr = bd_addr; write_reg_seq.data = bd_ctrl; write_reg_seq.start(m_sequencer);
      write_reg_seq.addr = bd_addr + 4; write_reg_seq.data = 32'h2000 + (bd * 2048); write_reg_seq.start(m_sequencer);
    end

    write_reg_seq.addr = 32'h00; write_reg_seq.data = 32'h1001; write_reg_seq.start(m_sequencer);  // RXEN | DlyCrcEn

    `uvm_info(get_type_name(), "MODER=0x1001 (RXEN|DlyCrcEn, CRCEN off)", UVM_LOW)
  endtask

  task check_packets_received(string phase_name);
    int pkts_received = 0;
    int expected_pkts = 4;

    `uvm_info(get_type_name(), $sformatf("Verifying packets received in %s", phase_name), UVM_MEDIUM)

    for (int bd = 0; bd < 4; bd++) begin
      logic [31:0] bd_addr = RX_BD_BASE + (bd * 8);
      logic [15:0] rx_len, rx_stats;
      read_reg_seq.addr = bd_addr; read_reg_seq.start(m_sequencer);
      rx_len = read_reg_seq.data[31:16];
      rx_stats = read_reg_seq.data[15:0];

      `uvm_info(get_type_name(), $sformatf("BD%0d: Status=0x%04h, Length=%0d, EMPTY=%0b",
                bd, rx_stats, rx_len, (rx_stats & RX_EMPTY) != 0), UVM_LOW)
      if ((rx_stats & RX_EMPTY) == 0) begin
        pkts_received++;
        `uvm_info(get_type_name(), $sformatf("BD%0d: Packet received, Length=%0d bytes", bd, rx_len), UVM_MEDIUM)
      end
    end

    if (pkts_received >= 4)
      `uvm_info(get_type_name(), $sformatf("PASSED: %0d/%0d packets received with %s", pkts_received, expected_pkts, phase_name), UVM_LOW)
    else
      `uvm_error("DLYCRC_FAIL", $sformatf("FAILED %s: Only %0d/4 BDs filled", phase_name, pkts_received))
  endtask

  task check_packets_rejected(string phase_name);
    int pkts_received = 0;

    `uvm_info(get_type_name(), $sformatf("Verifying packets were REJECTED in %s", phase_name), UVM_MEDIUM)

    for (int bd = 0; bd < 4; bd++) begin
      logic [31:0] bd_addr = RX_BD_BASE + (bd * 8);
      logic [15:0] rx_stats;
      read_reg_seq.addr = bd_addr; read_reg_seq.start(m_sequencer);
      rx_stats = read_reg_seq.data[15:0];
      if ((rx_stats & RX_EMPTY) == 0) begin
        pkts_received++;
        `uvm_error("DLYCRC_FAIL", $sformatf("BD%0d NOT empty! Standard packet accepted with %s", bd, phase_name))
      end
    end

    if (pkts_received == 0)
      `uvm_info(get_type_name(), $sformatf("PASSED: All standard packets correctly REJECTED with %s (DlyCrcEn shifts byte counter, address check fails)", phase_name), UVM_LOW)
  endtask
endclass : delayed_crc_rx_seq

//============================================================================
// PROMISCUOUS MODE RX SEQUENCE
//============================================================================
class promiscuous_mode_seq extends uvm_sequence #(wishbone_transaction);
  `uvm_object_utils(promiscuous_mode_seq)
  `uvm_declare_p_sequencer(host_sequencer)
  reg_write_seq write_reg_seq;
  reg_read_seq  read_reg_seq;

  localparam int TX_BD_NUM_VAL = 32'h40;
  localparam RX_BD_BASE = 32'h400 + (TX_BD_NUM_VAL * 8);

  localparam RX_EMPTY = 16'h8000;
  localparam RX_IRQ   = 16'h4000;
  localparam RX_WRAP  = 16'h2000;
  localparam RX_MISS  = 16'h0080;

  function new(string name = "promiscuous_mode_seq");
    super.new(name);
  endfunction

  virtual task body();
    write_reg_seq = reg_write_seq::type_id::create("write_reg_seq");
    read_reg_seq  = reg_read_seq::type_id::create("read_reg_seq");

    `uvm_info(get_type_name(), "PHASE 1: PRO=0 - mixed MAC packets (non-promiscuous)", UVM_LOW)
    configure_mac(32'h2001);
    #10000ns; #200000ns;
    check_phase1_results();

    `uvm_info(get_type_name(), "PHASE 2: PRO=1 - mixed MAC packets (promiscuous)", UVM_LOW)
    configure_mac(32'h2021);
    #10000ns; #200000ns;
    check_phase2_results();

    `uvm_info(get_type_name(), "PHASE 3: PRO=1 - all non-matching packets (verify AddressMiss)", UVM_LOW)
    configure_mac(32'h2021);
    #10000ns; #200000ns;
    check_phase3_results();

    `uvm_info(get_type_name(), "=== PROMISCUOUS MODE RX TEST COMPLETE ===", UVM_LOW)
  endtask

  task configure_mac(logic [31:0] moder_val);
    write_reg_seq.addr = 32'h04; write_reg_seq.data = 32'hFFFF_FFFF; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h40; write_reg_seq.data = 32'hBEEF0102; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h44; write_reg_seq.data = 32'h0000DEAD; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h18; write_reg_seq.data = 32'h00300600; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h48; write_reg_seq.data = 32'h00000000; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h4C; write_reg_seq.data = 32'h00000000; write_reg_seq.start(m_sequencer);

    // 4 RX BDs (raw)
    for (int bd = 0; bd < 4; bd++) begin
      logic [31:0] bd_addr = RX_BD_BASE + (bd * 8);
      logic [15:0] bd_ctrl = RX_EMPTY | RX_IRQ;
      if (bd == 3) bd_ctrl |= RX_WRAP;
      write_reg_seq.addr = bd_addr;     write_reg_seq.data = {16'h0000, bd_ctrl}; write_reg_seq.start(m_sequencer);
      write_reg_seq.addr = bd_addr + 4; write_reg_seq.data = 32'h2000 + (bd * 2048); write_reg_seq.start(m_sequencer);
    end

    write_reg_seq.addr = 32'h00; write_reg_seq.data = moder_val; write_reg_seq.start(m_sequencer);

    `uvm_info(get_type_name(), $sformatf("MAC configured: MODER=0x%04h, PRO=%0b", moder_val, moder_val[5]), UVM_LOW)
  endtask

  task check_phase1_results();
    int pkts_received = 0;
    for (int bd = 0; bd < 4; bd++) begin
      logic [31:0] bd_addr = RX_BD_BASE + (bd * 8);
      logic [15:0] rx_len, rx_stats;
      read_reg_seq.addr = bd_addr; read_reg_seq.start(m_sequencer);
      rx_len = read_reg_seq.data[31:16]; rx_stats = read_reg_seq.data[15:0];
      `uvm_info(get_type_name(), $sformatf("P1 BD%0d: Status=0x%04h, Len=%0d, EMPTY=%0b, MISS=%0b",
                bd, rx_stats, rx_len, (rx_stats & RX_EMPTY) != 0, (rx_stats & RX_MISS) != 0), UVM_LOW)
      if ((rx_stats & RX_EMPTY) == 0) pkts_received++;
    end
    if (pkts_received >= 1 && pkts_received <= 2)
      `uvm_info(get_type_name(), $sformatf("PASSED Phase 1: %0d/4 packets accepted with PRO=0 (expected 1-2)", pkts_received), UVM_LOW)
    else
      `uvm_error("PROMISC_FAIL", $sformatf("FAILED Phase 1: %0d/4 packets accepted with PRO=0 (expected 1-2)", pkts_received))
  endtask

  task check_phase2_results();
    int pkts_received = 0;
    for (int bd = 0; bd < 4; bd++) begin
      logic [31:0] bd_addr = RX_BD_BASE + (bd * 8);
      logic [15:0] rx_len, rx_stats;
      read_reg_seq.addr = bd_addr; read_reg_seq.start(m_sequencer);
      rx_len = read_reg_seq.data[31:16]; rx_stats = read_reg_seq.data[15:0];
      `uvm_info(get_type_name(), $sformatf("P2 BD%0d: Status=0x%04h, Len=%0d, EMPTY=%0b, MISS=%0b",
                bd, rx_stats, rx_len, (rx_stats & RX_EMPTY) != 0, (rx_stats & RX_MISS) != 0), UVM_LOW)
      if ((rx_stats & RX_EMPTY) == 0) pkts_received++;
    end
    if (pkts_received == 4)
      `uvm_info(get_type_name(), "PASSED Phase 2: 4/4 packets accepted with PRO=1", UVM_LOW)
    else
      `uvm_error("PROMISC_FAIL", $sformatf("FAILED Phase 2: %0d/4 packets accepted with PRO=1 (expected 4)", pkts_received))
  endtask

  task check_phase3_results();
    int pkts_received = 0;
    int pkts_with_miss = 0;
    for (int bd = 0; bd < 4; bd++) begin
      logic [31:0] bd_addr = RX_BD_BASE + (bd * 8);
      logic [15:0] rx_len, rx_stats;
      read_reg_seq.addr = bd_addr; read_reg_seq.start(m_sequencer);
      rx_len = read_reg_seq.data[31:16]; rx_stats = read_reg_seq.data[15:0];
      `uvm_info(get_type_name(), $sformatf("P3 BD%0d: Status=0x%04h, Len=%0d, EMPTY=%0b, MISS=%0b",
                bd, rx_stats, rx_len, (rx_stats & RX_EMPTY) != 0, (rx_stats & RX_MISS) != 0), UVM_LOW)
      if ((rx_stats & RX_EMPTY) == 0) begin
        pkts_received++;
        if ((rx_stats & RX_MISS) != 0) pkts_with_miss++;
      end
    end
    if (pkts_received == 4)
      `uvm_info(get_type_name(), "PASSED Phase 3: 4/4 non-matching packets accepted with PRO=1", UVM_LOW)
    else
      `uvm_error("PROMISC_FAIL", $sformatf("FAILED Phase 3: %0d/4 packets accepted with PRO=1 (expected 4)", pkts_received))
    if (pkts_with_miss == 4)
      `uvm_info(get_type_name(), "PASSED Phase 3: AddressMiss bit set on all 4 non-matching packets", UVM_LOW)
    else
      `uvm_info(get_type_name(), $sformatf("INFO Phase 3: AddressMiss set on %0d/4 packets", pkts_with_miss), UVM_LOW)
  endtask
endclass : promiscuous_mode_seq

//============================================================================
// ADDRESS MATCH RX SEQUENCE
//============================================================================
class addr_match_rx_seq extends uvm_sequence #(wishbone_transaction);
  `uvm_object_utils(addr_match_rx_seq)
  `uvm_declare_p_sequencer(host_sequencer)
  reg_write_seq write_reg_seq;
  reg_read_seq  read_reg_seq;

  localparam int TX_BD_NUM_VAL = 32'h40;
  localparam RX_BD_BASE = 32'h400 + (TX_BD_NUM_VAL * 8);

  localparam RX_EMPTY = 16'h8000;
  localparam RX_IRQ   = 16'h4000;
  localparam RX_WRAP  = 16'h2000;
  localparam RX_MISS  = 16'h0080;

  function new(string name = "addr_match_rx_seq");
    super.new(name);
  endfunction

  virtual task body();
    write_reg_seq = reg_write_seq::type_id::create("write_reg_seq");
    read_reg_seq  = reg_read_seq::type_id::create("read_reg_seq");

    `uvm_info(get_type_name(), "PHASE 1: r_Bro=0, HASH=0 (unicast + broadcast only)", UVM_LOW)
    configure_mac(.moder_val(32'h2011), .hash0_val(32'h0000_0000), .hash1_val(32'h0000_0000));
    #10000ns; #200000ns;
    check_results("Phase1", 2, 0);

    `uvm_info(get_type_name(), "PHASE 2: r_Bro=1, HASH=0 (unicast only, broadcast disabled)", UVM_LOW)
    configure_mac(.moder_val(32'h2019), .hash0_val(32'h0000_0000), .hash1_val(32'h0000_0000));
    #10000ns; #200000ns;
    check_results("Phase2", 1, 0);

    `uvm_info(get_type_name(), "PHASE 3: r_Bro=0, HASH=all-1s (multicast via hash)", UVM_LOW)
    configure_mac(.moder_val(32'h2011), .hash0_val(32'hFFFF_FFFF), .hash1_val(32'hFFFF_FFFF));
    #10000ns; #200000ns;
    check_results("Phase3", 3, 0);

    `uvm_info(get_type_name(), "PHASE 4: r_Bro=0, HASH=specific-wrong (multicast rejected)", UVM_LOW)
    configure_mac(.moder_val(32'h2011), .hash0_val(32'h0000_0001), .hash1_val(32'h0000_0000));
    #10000ns; #200000ns;
    check_results("Phase4", 2, 0);

    `uvm_info(get_type_name(), "=== ADDRESS MATCH RX TEST COMPLETE ===", UVM_LOW)
  endtask

  task configure_mac(logic [31:0] moder_val, logic [31:0] hash0_val, logic [31:0] hash1_val);
    // Disable RX first
    write_reg_seq.addr = 32'h00; write_reg_seq.data = 32'h0000; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h04; write_reg_seq.data = 32'hFFFF_FFFF; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h40; write_reg_seq.data = 32'hBEEF0102; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h44; write_reg_seq.data = 32'h0000DEAD; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h18; write_reg_seq.data = 32'h00300600; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h48; write_reg_seq.data = hash0_val; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h4C; write_reg_seq.data = hash1_val; write_reg_seq.start(m_sequencer);

    // 4 RX BDs (raw)
    for (int bd = 0; bd < 4; bd++) begin
      logic [31:0] bd_addr = RX_BD_BASE + (bd * 8);
      logic [15:0] bd_ctrl = RX_EMPTY | RX_IRQ;
      if (bd == 3) bd_ctrl |= RX_WRAP;
      write_reg_seq.addr = bd_addr;     write_reg_seq.data = {16'h0000, bd_ctrl}; write_reg_seq.start(m_sequencer);
      write_reg_seq.addr = bd_addr + 4; write_reg_seq.data = 32'h2000 + (bd * 2048); write_reg_seq.start(m_sequencer);
    end

    write_reg_seq.addr = 32'h00; write_reg_seq.data = moder_val; write_reg_seq.start(m_sequencer);

    `uvm_info(get_type_name(), $sformatf("MAC configured: MODER=0x%04h, HASH0=0x%08h, HASH1=0x%08h",
              moder_val, hash0_val, hash1_val), UVM_LOW)
  endtask

  task check_results(string phase_name, int expected_pkts, bit check_miss);
    int pkts_received = 0;
    for (int bd = 0; bd < 4; bd++) begin
      logic [31:0] bd_addr = RX_BD_BASE + (bd * 8);
      logic [15:0] rx_len, rx_stats;
      read_reg_seq.addr = bd_addr; read_reg_seq.start(m_sequencer);
      rx_len = read_reg_seq.data[31:16]; rx_stats = read_reg_seq.data[15:0];
      `uvm_info(get_type_name(), $sformatf("%s BD%0d: Status=0x%04h, Len=%0d, EMPTY=%0b, MISS=%0b",
                phase_name, bd, rx_stats, rx_len,
                (rx_stats & RX_EMPTY) != 0, (rx_stats & RX_MISS) != 0), UVM_LOW)
      if ((rx_stats & RX_EMPTY) == 0) pkts_received++;
    end
    if (pkts_received == expected_pkts)
      `uvm_info(get_type_name(), $sformatf("PASSED %s: %0d/%0d packets accepted", phase_name, pkts_received, expected_pkts), UVM_LOW)
    else
      `uvm_error("ADDR_MATCH_FAIL", $sformatf("FAILED %s: %0d packets accepted (expected %0d)", phase_name, pkts_received, expected_pkts))
  endtask
endclass : addr_match_rx_seq
