// fd_seq_lib.sv - Full-Duplex Sequences using raw Wishbone access

//============================================================================
// TX PAUSE SEQUENCE (FD-01)
// Command the DUT to send a PAUSE frame and verify the control frame
// contents on the MII interface.
//============================================================================
class tx_pause_seq extends uvm_sequence #(wishbone_transaction);
  `uvm_object_utils(tx_pause_seq)
  `uvm_declare_p_sequencer(host_sequencer)
  reg_write_seq write_reg_seq;
  reg_read_seq  read_reg_seq;

  // MODER: Full-Duplex (bit 10), PAD, CRC, TXEN
  // 0xA402 = PAD(15) | CRC(13) | FULLD(10) | TXEN(1)
  localparam MODER_CONF = 32'h0000_A402;

  // CTRLMODER: TxFlow = bit 2
  localparam CTRLMODER_TXFLOW = 32'h0000_0004;

  // TX_CTRL: TxPauseRq = bit 16
  localparam TX_CTRL_PAUSERQ = 32'h0001_0000;

  // INT_SOURCE bits
  localparam INT_TXC = 32'h0000_0020;  // Transmit Control Frame

  // Known MAC address for verification
  localparam MAC_HI = 32'h0000_0011;  // MAC[47:32] = 00:11
  localparam MAC_LO = 32'h2233_4455;  // MAC[31:0]  = 22:33:44:55

  // Known pause timer value
  localparam [15:0] PAUSE_TV = 16'hABCD;

  // Expected PAUSE frame (first 18 bytes)
  // DA: 01:80:C2:00:00:01, SA: 00:11:22:33:44:55
  // Type: 88:08, Opcode: 00:01, PauseTV: AB:CD
  localparam byte unsigned EXPECTED_FRAME [18] = '{
    8'h01, 8'h80, 8'hC2, 8'h00, 8'h00, 8'h01,  // DA
    8'h00, 8'h11, 8'h22, 8'h33, 8'h44, 8'h55,  // SA
    8'h88, 8'h08,                                // Type
    8'h00, 8'h01,                                // Opcode
    8'hAB, 8'hCD                                 // PauseTV
  };

  function new(string name = "tx_pause_seq");
    super.new(name);
  endfunction

  virtual task body();
    phy_agent_config m_phy_cfg;
    logic [31:0] int_status;
    byte unsigned captured_frame[$];
    bit  all_ok = 1;
    write_reg_seq = reg_write_seq::type_id::create("write_reg_seq");
    read_reg_seq  = reg_read_seq::type_id::create("read_reg_seq");

    `uvm_info(get_type_name(), "FD-01: TX PAUSE Frame Test", UVM_LOW)

    // Get PHY config for MII interface access
    if (!uvm_config_db#(phy_agent_config)::get(null, "uvm_test_top.m_env.m_phy_agent*", "config", m_phy_cfg))
      `uvm_fatal("SEQ", "Cannot get phy_agent_config")
    m_phy_cfg.collisions_remaining = 0;

    // 1. Configure MAC — Full Duplex via RAL
    write_reg_seq.addr = 32'h20; write_reg_seq.data = 32'd1; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h18; write_reg_seq.data = 32'h0040_0600; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h00; write_reg_seq.data = MODER_CONF; write_reg_seq.start(m_sequencer);

    // 2. Set known MAC address (for SA verification) via RAL
    write_reg_seq.addr = 32'h44; write_reg_seq.data = MAC_HI; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h40; write_reg_seq.data = MAC_LO; write_reg_seq.start(m_sequencer);

    // 3. Enable TX flow control via RAL
    write_reg_seq.addr = 32'h24; write_reg_seq.data = CTRLMODER_TXFLOW; write_reg_seq.start(m_sequencer);

    // 4. Clear interrupts via RAL
    write_reg_seq.addr = 32'h04; write_reg_seq.data = 32'hFFFF_FFFF; write_reg_seq.start(m_sequencer);

    // 5. Trigger PAUSE frame via RAL
    write_reg_seq.addr = 32'h50; write_reg_seq.data = TX_CTRL_PAUSERQ | {16'h0, PAUSE_TV}; write_reg_seq.start(m_sequencer);

    `uvm_info(get_type_name(), $sformatf("PAUSE request sent. PauseTV=0x%04h", PAUSE_TV), UVM_LOW)

    // 6. Capture frame on MII (nibble-by-nibble)
    begin
      logic [3:0] nib;
      int nib_count = 0;
      bit in_sfd = 0;

      // Wait for tx_en to go HIGH
      fork
        begin
          wait (m_phy_cfg.vif.tx_en === 1'b1);
        end
        begin
          #500_000ns;
          `uvm_fatal("SEQ", "TIMEOUT: tx_en never asserted for PAUSE frame")
        end
      join_any
      disable fork;

      // Skip preamble (0x5) and SFD (0xD)
      while (m_phy_cfg.vif.tx_en === 1'b1) begin
        @(posedge m_phy_cfg.vif.tx_clk);
        nib = m_phy_cfg.vif.txd;

        if (!in_sfd) begin
          if (nib == 4'hD) begin
            in_sfd = 1;
            nib_count = 0;
          end
        end else begin
          if (nib_count % 2 == 0) begin
            captured_frame.push_back({4'h0, nib});
          end else begin
            captured_frame[captured_frame.size()-1] = {nib, captured_frame[captured_frame.size()-1][3:0]};
          end
          nib_count++;
        end
      end

      `uvm_info(get_type_name(), $sformatf("Captured %0d bytes from MII", captured_frame.size()), UVM_LOW)
    end

    // 7. Verify frame contents
    if (captured_frame.size() < 18) begin
      `uvm_error(get_type_name(), $sformatf(
        "FAIL: Captured only %0d bytes, expected >= 18", captured_frame.size()))
      all_ok = 0;
    end else begin
      for (int i = 0; i < 18; i++) begin
        if (captured_frame[i] !== EXPECTED_FRAME[i]) begin
          `uvm_error(get_type_name(), $sformatf(
            "FAIL: Byte[%0d] mismatch: got=0x%02h expected=0x%02h",
            i, captured_frame[i], EXPECTED_FRAME[i]))
          all_ok = 0;
        end
      end

      // Verify padding bytes (18-59) are zero
      for (int i = 18; i < 60 && i < captured_frame.size(); i++) begin
        if (captured_frame[i] !== 8'h00) begin
          `uvm_error(get_type_name(), $sformatf(
            "FAIL: Pad byte[%0d] = 0x%02h, expected 0x00", i, captured_frame[i]))
          all_ok = 0;
        end
      end

      `uvm_info(get_type_name(), $sformatf(
        "Frame: DA=%02h:%02h:%02h:%02h:%02h:%02h SA=%02h:%02h:%02h:%02h:%02h:%02h Type=%02h%02h Op=%02h%02h TV=%02h%02h",
        captured_frame[0], captured_frame[1], captured_frame[2],
        captured_frame[3], captured_frame[4], captured_frame[5],
        captured_frame[6], captured_frame[7], captured_frame[8],
        captured_frame[9], captured_frame[10], captured_frame[11],
        captured_frame[12], captured_frame[13],
        captured_frame[14], captured_frame[15],
        captured_frame[16], captured_frame[17]), UVM_LOW)
    end

    // 8. Verify TXC interrupt via RAL
    #500ns;
    read_reg_seq.addr = 32'h04; read_reg_seq.start(m_sequencer); int_status = read_reg_seq.data;

    `uvm_info(get_type_name(), $sformatf("INT_SOURCE = 0x%08h", int_status), UVM_LOW)

    if ((int_status & INT_TXC) == 0) begin
      `uvm_error(get_type_name(), $sformatf(
        "FAIL: TXC interrupt not set. INT_SOURCE=0x%08h", int_status))
      all_ok = 0;
    end

    // 9. Final verdict
    if (all_ok)
      `uvm_info(get_type_name(), $sformatf(
        "PASS: PAUSE frame verified. %0d bytes captured, TXC=1.", captured_frame.size()), UVM_LOW)
    else
      `uvm_error(get_type_name(), "FAIL: PAUSE frame verification failed.")

  endtask : body

endclass : tx_pause_seq

//============================================================================
// RX PAUSE SEQUENCE (FD-02)
// Send a PAUSE frame to the DUT while it is transmitting.
// Verify that the DUT pauses TX for the specified pause duration.
//============================================================================
class rx_pause_seq extends uvm_sequence #(wishbone_transaction);
  `uvm_object_utils(rx_pause_seq)
  `uvm_declare_p_sequencer(host_sequencer)
  reg_write_seq write_reg_seq;
  reg_read_seq  read_reg_seq;

  // Buffer Descriptors (not in RAL)
  localparam BD0_STATUS = 32'h400;
  localparam BD0_PTR    = 32'h404;
  localparam BD1_STATUS = 32'h408;
  localparam BD1_PTR    = 32'h40C;
  localparam RX_BD0_STATUS = 32'h410;
  localparam RX_BD0_PTR    = 32'h414;
  localparam TX_BUFFER  = 32'h2000;
  localparam TX_BUFFER1 = 32'h2800;
  localparam RX_BUFFER  = 32'h4000;

  // MODER bits
  localparam MODER_TX_ONLY = 32'h0000_A402;  // PAD|CRC|FULLD|TXEN (no RXEN)
  localparam MODER_TXRX    = 32'h0000_A403;  // PAD|CRC|FULLD|TXEN|RXEN

  // CTRLMODER: RxFlow = bit 1
  localparam CTRLMODER_RXFLOW = 32'h0000_0002;

  // BD Status bits
  localparam BIT_RD   = 16'h8000;
  localparam BIT_IRQ  = 16'h4000;
  localparam BIT_WRAP = 16'h2000;
  localparam BIT_PAD  = 16'h1000;
  localparam BIT_CRC  = 16'h0800;

  // INT bits
  localparam INT_TXB = 32'h0000_0001;

  // PAUSE frame parameters
  localparam [15:0] PAUSE_TV = 16'h0005;

  // MAC address
  localparam MAC_HI = 32'h0000_0011;
  localparam MAC_LO = 32'h2233_4455;

  function new(string name = "rx_pause_seq");
    super.new(name);
  endfunction

  // CRC-32 computation for Ethernet
  function automatic bit [31:0] compute_crc(byte unsigned data[$]);
    bit [31:0] crc, poly;
    poly = 32'hEDB88320;
    crc = 32'hFFFFFFFF;
    foreach (data[i]) begin
      crc = crc ^ data[i];
      repeat (8) begin
        if (crc[0]) crc = (crc >> 1) ^ poly;
        else        crc = (crc >> 1);
      end
    end
    return ~crc;
  endfunction

  // Drive a single byte on MII RX (low nibble first)
  task drive_rx_byte(virtual mii_if vif, byte unsigned b);
    @(posedge vif.rx_clk); vif.rxd <= b[3:0];
    @(posedge vif.rx_clk); vif.rxd <= b[7:4];
  endtask

  virtual task body();
    int pkt_len = 100;
    phy_agent_config m_phy_cfg;
    logic [31:0] bd_status;
    logic [31:0] rdata;
    time t_bd0_end, t_bd1_start, gap_ns;
    bit all_ok = 1;
    write_reg_seq = reg_write_seq::type_id::create("write_reg_seq");
    read_reg_seq  = reg_read_seq::type_id::create("read_reg_seq");

    `uvm_info(get_type_name(), "FD-02: RX PAUSE Frame — Transmission Pause Verification", UVM_LOW)

    // Get PHY config
    if (!uvm_config_db#(phy_agent_config)::get(null, "uvm_test_top.m_env.m_phy_agent*", "config", m_phy_cfg))
      `uvm_fatal("SEQ", "Cannot get phy_agent_config")
    m_phy_cfg.collisions_remaining = 0;

    // 1. Configure MAC — Full Duplex, TX+RX enabled via RAL
    write_reg_seq.addr = 32'h20; write_reg_seq.data = 32'd2; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h0C; write_reg_seq.data = 32'h15; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h18; write_reg_seq.data = 32'h0040_0600; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h00; write_reg_seq.data = MODER_TX_ONLY; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h44; write_reg_seq.data = MAC_HI; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h40; write_reg_seq.data = MAC_LO; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h24; write_reg_seq.data = CTRLMODER_RXFLOW; write_reg_seq.start(m_sequencer);

    // 2. Set up RX BD (for PAUSE frame reception) — raw
    write_reg_seq.addr = RX_BD0_STATUS;
    write_reg_seq.data = {(BIT_RD | BIT_IRQ | BIT_WRAP), 16'h0};
    write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = RX_BD0_PTR;
    write_reg_seq.data = RX_BUFFER;
    write_reg_seq.start(m_sequencer);

    // 3. Load TX packet data via DMA (BD0 and BD1)
    begin
      uvm_component comp;
      uvm_sequencer_base dma_seqr;
      reg_write_seq mem_seq;

      comp = uvm_top.find("uvm_test_top.m_env.m_dma_agent.m_sequencer");
      if (comp == null) `uvm_fatal("SEQ", "Could not find DMA sequencer")
      if (!$cast(dma_seqr, comp)) `uvm_fatal("SEQ", "DMA sequencer cast failed")

      mem_seq = reg_write_seq::type_id::create("mem_seq");

      for (int i = 0; i < pkt_len; i += 4) begin
        logic [31:0] word = 0;
        for (int b = 0; b < 4 && (i + b) < pkt_len; b++)
          word |= (((i + b) & 8'hFF) << (b * 8));
        mem_seq.addr = TX_BUFFER + i;  mem_seq.data = word; mem_seq.start(dma_seqr);
      end
      for (int i = 0; i < pkt_len; i += 4) begin
        logic [31:0] word = 0;
        for (int b = 0; b < 4 && (i + b) < pkt_len; b++)
          word |= (((i + b) & 8'hFF) << (b * 8));
        mem_seq.addr = TX_BUFFER1 + i; mem_seq.data = word; mem_seq.start(dma_seqr);
      end
    end

    // 4. Clear interrupts, program both TX BDs as ready — raw for BDs, RAL for INT
    write_reg_seq.addr = 32'h04; write_reg_seq.data = 32'hFFFF_FFFF; write_reg_seq.start(m_sequencer);

    write_reg_seq.addr = BD0_PTR; write_reg_seq.data = TX_BUFFER;  write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = BD1_PTR; write_reg_seq.data = TX_BUFFER1; write_reg_seq.start(m_sequencer);

    write_reg_seq.addr = BD0_STATUS;
    write_reg_seq.data = (pkt_len << 16) | (BIT_RD | BIT_IRQ | BIT_PAD | BIT_CRC);
    write_reg_seq.start(m_sequencer);

    write_reg_seq.addr = BD1_STATUS;
    write_reg_seq.data = (pkt_len << 16) | (BIT_RD | BIT_IRQ | BIT_WRAP | BIT_PAD | BIT_CRC);
    write_reg_seq.start(m_sequencer);

    `uvm_info(get_type_name(), "Both TX BDs ready. DUT should start transmitting BD0.", UVM_LOW)

    // 5. Wait for BD0 TX to start, then inject PAUSE frame
    wait (m_phy_cfg.vif.tx_en === 1'b1);
    `uvm_info(get_type_name(), "BD0 TX started. Enabling RXEN and injecting PAUSE frame...", UVM_LOW)

    // Enable RXEN via RAL
    write_reg_seq.addr = 32'h00; write_reg_seq.data = MODER_TXRX; write_reg_seq.start(m_sequencer);

    // Now take over CRS for PAUSE injection
    m_phy_cfg.crs_override = 1;

    repeat(20) @(posedge m_phy_cfg.vif.rx_clk);

    // Build and inject PAUSE frame
    begin
      byte unsigned pause_data[$];
      bit [31:0] crc;
      byte unsigned crc_bytes[4];

      pause_data = '{8'h01, 8'h80, 8'hC2, 8'h00, 8'h00, 8'h01,
                     8'h00, 8'hCC, 8'hDD, 8'hEE, 8'hFF, 8'h00,
                     8'h88, 8'h08,
                     8'h00, 8'h01,
                     PAUSE_TV[15:8], PAUSE_TV[7:0]};
      while (pause_data.size() < 60) pause_data.push_back(8'h00);

      crc = compute_crc(pause_data);
      crc_bytes[0] = crc[7:0];   crc_bytes[1] = crc[15:8];
      crc_bytes[2] = crc[23:16]; crc_bytes[3] = crc[31:24];

      m_phy_cfg.vif.crs   <= 1'b1;
      @(posedge m_phy_cfg.vif.rx_clk);
      m_phy_cfg.vif.rx_dv <= 1'b1;
      m_phy_cfg.vif.rxd   <= 4'h5;
      repeat(14) @(posedge m_phy_cfg.vif.rx_clk) m_phy_cfg.vif.rxd <= 4'h5;
      @(posedge m_phy_cfg.vif.rx_clk) m_phy_cfg.vif.rxd <= 4'hD;

      foreach (pause_data[i]) drive_rx_byte(m_phy_cfg.vif, pause_data[i]);

      for (int i = 0; i < 4; i++) drive_rx_byte(m_phy_cfg.vif, crc_bytes[i]);

      @(posedge m_phy_cfg.vif.rx_clk);
      m_phy_cfg.vif.rx_dv <= 1'b0;
      m_phy_cfg.vif.rxd   <= 4'h0;
      @(posedge m_phy_cfg.vif.rx_clk);
      m_phy_cfg.vif.crs   <= 1'b0;

      `uvm_info(get_type_name(), $sformatf(
        "PAUSE frame injected (PauseTV=%0d slots). Now monitoring TX gap...", PAUSE_TV), UVM_LOW)
    end

    // 6. Measure pause gap: BD0 end → BD1 start
    wait (m_phy_cfg.vif.tx_en === 1'b0);
    t_bd0_end = $time;
    `uvm_info(get_type_name(), $sformatf("BD0 TX ended at t=%0t", t_bd0_end), UVM_MEDIUM)

    wait (m_phy_cfg.vif.tx_en === 1'b1);
    t_bd1_start = $time;
    `uvm_info(get_type_name(), $sformatf("BD1 TX started at t=%0t", t_bd1_start), UVM_MEDIUM)

    gap_ns = t_bd1_start - t_bd0_end;

    wait (m_phy_cfg.vif.tx_en === 1'b0);

    // 7. Verify pause gap
    begin
      int expected_pause = PAUSE_TV * 5120;
      int min_gap = expected_pause / 2;
      int max_gap = expected_pause * 4;

      `uvm_info(get_type_name(), $sformatf(
        "PAUSE GAP: measured=%0t, expected_pause=%0dns, bounds=[%0d, %0d]",
        gap_ns, expected_pause, min_gap, max_gap), UVM_LOW)

      if (gap_ns < min_gap) begin
        `uvm_error(get_type_name(), $sformatf(
          "FAIL: Gap too short (%0t). PAUSE not honored.", gap_ns))
        all_ok = 0;
      end else if (gap_ns > max_gap) begin
        `uvm_error(get_type_name(), $sformatf(
          "FAIL: Gap too long (%0t). DUT may be stuck.", gap_ns))
        all_ok = 0;
      end
    end

    // 8. Check BD1 completed — raw BD read
    #2000ns;
    read_reg_seq.addr = BD1_STATUS;
    read_reg_seq.start(m_sequencer);
    bd_status = read_reg_seq.data;

    if ((bd_status & BIT_RD) != 0) begin
      `uvm_error(get_type_name(), "FAIL: BD1 still Ready — TX did not complete")
      all_ok = 0;
    end

    // Check TXB interrupt via RAL
    read_reg_seq.addr = 32'h04; read_reg_seq.start(m_sequencer); rdata = read_reg_seq.data;
    `uvm_info(get_type_name(), $sformatf("INT_SOURCE = 0x%08h", rdata), UVM_LOW)

    if ((rdata & INT_TXB) == 0) begin
      `uvm_error(get_type_name(), "FAIL: TXB interrupt not set")
      all_ok = 0;
    end

    // 9. Cleanup and verdict
    m_phy_cfg.crs_override = 0;

    if (all_ok)
      `uvm_info(get_type_name(), $sformatf(
        "PASS: DUT paused TX for %0t after PAUSE(TV=%0d). Both BDs completed.", gap_ns, PAUSE_TV), UVM_LOW)
    else
      `uvm_error(get_type_name(), "FAIL: RX PAUSE frame test failed.")

  endtask : body

endclass : rx_pause_seq

//============================================================================
// PAUSE TIMER SEQUENCE (FD-03)
// Test PAUSE frame reception and timer (TxPauseTV) across multiple scenarios:
//   A) PauseTV=3   — short pause
//   B) PauseTV=10  — longer pause (proportionality)
//   C) PauseTV=0   — no pause (edge case)
//   D) TV=3 → TV=8 — timer reload during active pause
//============================================================================
class pause_timer_seq extends uvm_sequence #(wishbone_transaction);
  `uvm_object_utils(pause_timer_seq)
  `uvm_declare_p_sequencer(host_sequencer)
  reg_write_seq write_reg_seq;
  reg_read_seq  read_reg_seq;

  // Buffer Descriptors (not in RAL)
  localparam BD0_STATUS = 32'h400;
  localparam BD0_PTR    = 32'h404;
  localparam BD1_STATUS = 32'h408;
  localparam BD1_PTR    = 32'h40C;
  localparam RX_BD0_STATUS = 32'h410;
  localparam RX_BD0_PTR    = 32'h414;
  localparam TX_BUFFER  = 32'h2000;
  localparam TX_BUFFER1 = 32'h2800;
  localparam RX_BUFFER  = 32'h4000;

  localparam MODER_TX_ONLY = 32'h0000_A402;
  localparam MODER_TXRX    = 32'h0000_A403;
  localparam CTRLMODER_RXFLOW = 32'h0000_0002;

  localparam BIT_RD   = 16'h8000;
  localparam BIT_IRQ  = 16'h4000;
  localparam BIT_WRAP = 16'h2000;
  localparam BIT_PAD  = 16'h1000;
  localparam BIT_CRC  = 16'h0800;
  localparam INT_TXB  = 32'h0000_0001;

  localparam MAC_HI = 32'h0000_0011;
  localparam MAC_LO = 32'h2233_4455;
  localparam SLOT_NS = 5120;  // 128 rx_clk × 40ns at 25 MHz

  phy_agent_config m_phy_cfg;
  bit all_ok;

  function new(string name = "pause_timer_seq");
    super.new(name);
  endfunction

  function automatic bit [31:0] compute_crc(byte unsigned data[$]);
    bit [31:0] crc;
    crc = 32'hFFFFFFFF;
    foreach (data[i]) begin
      crc = crc ^ data[i];
      repeat (8) begin
        if (crc[0]) crc = (crc >> 1) ^ 32'hEDB88320;
        else        crc = (crc >> 1);
      end
    end
    return ~crc;
  endfunction

  task drive_rx_byte(byte unsigned b);
    @(posedge m_phy_cfg.vif.rx_clk); m_phy_cfg.vif.rxd <= b[3:0];
    @(posedge m_phy_cfg.vif.rx_clk); m_phy_cfg.vif.rxd <= b[7:4];
  endtask

  task inject_pause_frame(int unsigned pause_tv);
    byte unsigned pd[$];
    bit [31:0] crc;
    byte unsigned cb[4];

    pd = '{8'h01, 8'h80, 8'hC2, 8'h00, 8'h00, 8'h01,
           8'h00, 8'hCC, 8'hDD, 8'hEE, 8'hFF, 8'h00,
           8'h88, 8'h08, 8'h00, 8'h01,
           pause_tv[15:8], pause_tv[7:0]};
    while (pd.size() < 60) pd.push_back(8'h00);

    crc = compute_crc(pd);
    cb[0] = crc[7:0]; cb[1] = crc[15:8]; cb[2] = crc[23:16]; cb[3] = crc[31:24];

    m_phy_cfg.vif.crs <= 1'b1;
    @(posedge m_phy_cfg.vif.rx_clk);
    m_phy_cfg.vif.rx_dv <= 1'b1;
    m_phy_cfg.vif.rxd   <= 4'h5;
    repeat(14) @(posedge m_phy_cfg.vif.rx_clk) m_phy_cfg.vif.rxd <= 4'h5;
    @(posedge m_phy_cfg.vif.rx_clk) m_phy_cfg.vif.rxd <= 4'hD;

    foreach (pd[i]) drive_rx_byte(pd[i]);
    for (int i = 0; i < 4; i++) drive_rx_byte(cb[i]);

    @(posedge m_phy_cfg.vif.rx_clk);
    m_phy_cfg.vif.rx_dv <= 1'b0;
    m_phy_cfg.vif.rxd   <= 4'h0;
    @(posedge m_phy_cfg.vif.rx_clk);
    m_phy_cfg.vif.crs   <= 1'b0;
  endtask

  // Arm BDs, start TX, enable RXEN, return after BD0 TX starts
  task start_subtest(int pkt_len);
    // Reset MAC to clear BD pointers via RAL
    write_reg_seq.addr = 32'h00; write_reg_seq.data = 32'h0; write_reg_seq.start(m_sequencer);
    #100ns;
    write_reg_seq.addr = 32'h04; write_reg_seq.data = 32'hFFFF_FFFF; write_reg_seq.start(m_sequencer);
    // RX BD — raw
    write_reg_seq.addr = RX_BD0_STATUS;
    write_reg_seq.data = {(BIT_RD | BIT_IRQ | BIT_WRAP), 16'h0};
    write_reg_seq.start(m_sequencer);
    // Re-enable TX via RAL
    write_reg_seq.addr = 32'h00; write_reg_seq.data = MODER_TX_ONLY; write_reg_seq.start(m_sequencer);

    // BD setup — raw
    write_reg_seq.addr = BD0_PTR; write_reg_seq.data = TX_BUFFER;  write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = BD1_PTR; write_reg_seq.data = TX_BUFFER1; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = BD0_STATUS;
    write_reg_seq.data = (pkt_len << 16) | (BIT_RD | BIT_IRQ | BIT_PAD | BIT_CRC);
    write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = BD1_STATUS;
    write_reg_seq.data = (pkt_len << 16) | (BIT_RD | BIT_IRQ | BIT_WRAP | BIT_PAD | BIT_CRC);
    write_reg_seq.start(m_sequencer);

    wait (m_phy_cfg.vif.tx_en === 1'b1);
    // Enable RXEN via RAL
    write_reg_seq.addr = 32'h00; write_reg_seq.data = MODER_TXRX; write_reg_seq.start(m_sequencer);
    m_phy_cfg.crs_override = 1;
    repeat(20) @(posedge m_phy_cfg.vif.rx_clk);
  endtask

  // Measure gap between BD0 end and BD1 start, wait for BD1 to complete
  task measure_gap(output time gap);
    time t0, t1;
    wait (m_phy_cfg.vif.tx_en === 1'b0);
    t0 = $time;
    wait (m_phy_cfg.vif.tx_en === 1'b1);
    t1 = $time;
    gap = t1 - t0;
    wait (m_phy_cfg.vif.tx_en === 1'b0);
    m_phy_cfg.crs_override = 0;
    #2000ns;
  endtask

  task check_bounds(string name, time gap, int min_ns, int max_ns);
    if (gap < min_ns || gap > max_ns) begin
      `uvm_error(get_type_name(), $sformatf(
        "%s FAIL: gap=%0t, bounds=[%0d, %0d]", name, gap, min_ns, max_ns))
      all_ok = 0;
    end else
      `uvm_info(get_type_name(), $sformatf(
        "%s PASS: gap=%0t, bounds=[%0d, %0d]", name, gap, min_ns, max_ns), UVM_LOW)
  endtask

  virtual task body();
    int pkt_len = 100;
    int pkt_len_big = 200;
    time gap_a, gap_b, gap_c, gap_d;
    write_reg_seq = reg_write_seq::type_id::create("write_reg_seq");
    read_reg_seq  = reg_read_seq::type_id::create("read_reg_seq");
    all_ok = 1;

    `uvm_info(get_type_name(), "FD-03: PAUSE Timer — Multi-scenario Verification", UVM_LOW)

    if (!uvm_config_db#(phy_agent_config)::get(null, "uvm_test_top.m_env.m_phy_agent*", "config", m_phy_cfg))
      `uvm_fatal("SEQ", "Cannot get phy_agent_config")
    m_phy_cfg.collisions_remaining = 0;

    // === ONE-TIME SETUP via RAL ===
    write_reg_seq.addr = 32'h20; write_reg_seq.data = 32'd2; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h0C; write_reg_seq.data = 32'h15; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h18; write_reg_seq.data = 32'h0040_0600; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h44; write_reg_seq.data = MAC_HI; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h40; write_reg_seq.data = MAC_LO; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h24; write_reg_seq.data = CTRLMODER_RXFLOW; write_reg_seq.start(m_sequencer);
    // RX BD pointer — raw
    write_reg_seq.addr = RX_BD0_PTR; write_reg_seq.data = RX_BUFFER; write_reg_seq.start(m_sequencer);

    // Load TX data via DMA (200 bytes each buffer)
    begin
      uvm_component comp;
      uvm_sequencer_base dma_seqr;
      reg_write_seq mem_seq;
      comp = uvm_top.find("uvm_test_top.m_env.m_dma_agent.m_sequencer");
      if (comp == null) `uvm_fatal("SEQ", "Could not find DMA sequencer")
      if (!$cast(dma_seqr, comp)) `uvm_fatal("SEQ", "DMA sequencer cast failed")
      mem_seq = reg_write_seq::type_id::create("mem_seq");
      for (int i = 0; i < pkt_len_big; i += 4) begin
        logic [31:0] word = 0;
        for (int b = 0; b < 4 && (i + b) < pkt_len_big; b++)
          word |= (((i + b) & 8'hFF) << (b * 8));
        mem_seq.addr = TX_BUFFER + i; mem_seq.data = word; mem_seq.start(dma_seqr);
      end
      for (int i = 0; i < pkt_len_big; i += 4) begin
        logic [31:0] word = 0;
        for (int b = 0; b < 4 && (i + b) < pkt_len_big; b++)
          word |= (((i + b) & 8'hFF) << (b * 8));
        mem_seq.addr = TX_BUFFER1 + i; mem_seq.data = word; mem_seq.start(dma_seqr);
      end
    end

    // =====================================================
    // SUB-TEST A: PauseTV = 3 (short pause)
    // =====================================================
    `uvm_info(get_type_name(), "--- Sub-test A: PauseTV=3 ---", UVM_LOW)
    start_subtest(pkt_len);
    inject_pause_frame(3);
    measure_gap(gap_a);
    check_bounds("A(TV=3)", gap_a, 3*SLOT_NS/2, 3*SLOT_NS*3);

    // =====================================================
    // SUB-TEST B: PauseTV = 10 (longer pause)
    // =====================================================
    `uvm_info(get_type_name(), "--- Sub-test B: PauseTV=10 ---", UVM_LOW)
    start_subtest(pkt_len);
    inject_pause_frame(10);
    measure_gap(gap_b);
    check_bounds("B(TV=10)", gap_b, 10*SLOT_NS/2, 10*SLOT_NS*3);

    // =====================================================
    // SUB-TEST C: PauseTV = 0 (no pause)
    // =====================================================
    `uvm_info(get_type_name(), "--- Sub-test C: PauseTV=0 ---", UVM_LOW)
    start_subtest(pkt_len);
    inject_pause_frame(0);
    measure_gap(gap_c);
    check_bounds("C(TV=0)", gap_c, 0, SLOT_NS);

    // =====================================================
    // SUB-TEST D: Timer reload TV=3 → TV=8
    // =====================================================
    `uvm_info(get_type_name(), "--- Sub-test D: Reload TV=3->8 ---", UVM_LOW)
    start_subtest(pkt_len_big);
    inject_pause_frame(3);
    repeat(30) @(posedge m_phy_cfg.vif.rx_clk);
    inject_pause_frame(8);
    measure_gap(gap_d);
    check_bounds("D(reload->8)", gap_d, 8*SLOT_NS/2, 8*SLOT_NS*3);

    // =====================================================
    // CROSS-CHECKS
    // =====================================================
    if (gap_b <= gap_a) begin
      `uvm_error(get_type_name(), $sformatf(
        "CROSS FAIL: gap_b(%0t) should be > gap_a(%0t) — timer not proportional", gap_b, gap_a))
      all_ok = 0;
    end
    if (gap_d <= gap_a) begin
      `uvm_error(get_type_name(), $sformatf(
        "CROSS FAIL: gap_d(%0t) should be > gap_a(%0t) — timer reload failed", gap_d, gap_a))
      all_ok = 0;
    end
    if (gap_c >= gap_a) begin
      `uvm_error(get_type_name(), $sformatf(
        "CROSS FAIL: gap_c(%0t) should be < gap_a(%0t) — TV=0 should not pause", gap_c, gap_a))
      all_ok = 0;
    end

    // =====================================================
    // FINAL VERDICT
    // =====================================================
    `uvm_info(get_type_name(), $sformatf(
      "Summary: A=%0t B=%0t C=%0t D=%0t", gap_a, gap_b, gap_c, gap_d), UVM_LOW)
    if (all_ok)
      `uvm_info(get_type_name(), "PASS: All 4 PAUSE timer sub-tests passed.", UVM_LOW)
    else
      `uvm_error(get_type_name(), "FAIL: PAUSE timer test failed.")

  endtask : body

endclass : pause_timer_seq
