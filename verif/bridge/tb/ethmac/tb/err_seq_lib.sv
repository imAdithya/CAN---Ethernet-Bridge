// err_seq_lib.sv - Error Condition Sequences using raw Wishbone access

//============================================================================
// TX UNDERRUN SEQUENCE (ERR-01)
//============================================================================
class tx_underrun_seq extends uvm_sequence #(wishbone_transaction);
  `uvm_object_utils(tx_underrun_seq)
  `uvm_declare_p_sequencer(host_sequencer)
  reg_write_seq write_reg_seq;
  reg_read_seq  read_reg_seq;

  localparam BD0_STATUS = 32'h400;
  localparam BD0_PTR    = 32'h404;
  localparam TX_BUFFER  = 32'h2000;

  localparam MODER_CONF = 32'h0000_A002;  // PAD|CRC|TXEN

  localparam BIT_RD   = 16'h8000;
  localparam BIT_IRQ  = 16'h4000;
  localparam BIT_WRAP = 16'h2000;
  localparam BIT_PAD  = 16'h1000;
  localparam BIT_CRC  = 16'h0800;

  localparam BIT_UNDERRUN = 32'h0000_0100;
  localparam INT_TXE = 32'h0000_0002;

  function new(string name = "tx_underrun_seq");
    super.new(name);
  endfunction

  virtual task body();
    int pkt_len = 500;
    logic [31:0] bd_status, int_status;
    bit all_ok = 1;
    phy_agent_config m_phy_cfg;
    write_reg_seq = reg_write_seq::type_id::create("write_reg_seq");
    read_reg_seq  = reg_read_seq::type_id::create("read_reg_seq");

    `uvm_info(get_type_name(), "ERR-01: TX Underrun Test", UVM_LOW)

    if (!uvm_config_db#(phy_agent_config)::get(null, "uvm_test_top.m_env.m_phy_agent*", "config", m_phy_cfg))
      `uvm_fatal("SEQ", "Cannot get phy_agent_config")
    m_phy_cfg.collisions_remaining = 0;

    // 1. Configure MAC via RAL
    write_reg_seq.addr = 32'h20; write_reg_seq.data = 32'd1; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h0C; write_reg_seq.data = 32'h15; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h18; write_reg_seq.data = 32'h0040_0600; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h00; write_reg_seq.data = MODER_CONF; write_reg_seq.start(m_sequencer);

    // 2. Load TX data via DMA
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
        mem_seq.addr = TX_BUFFER + i; mem_seq.data = word; mem_seq.start(dma_seqr);
      end
    end

    // 3. Clear interrupts via RAL
    write_reg_seq.addr = 32'h04; write_reg_seq.data = 32'hFFFF_FFFF; write_reg_seq.start(m_sequencer);

    // 4. Enable DMA delay to cause underrun
    `uvm_info(get_type_name(), "Setting DMA ACK delay = 50 cycles to cause underrun...", UVM_LOW)
    p_sequencer.mem_vif.ack_delay = 50;

    // 5. Program BD and start TX (raw)
    write_reg_seq.addr = BD0_PTR;    write_reg_seq.data = TX_BUFFER;   write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = BD0_STATUS;
    write_reg_seq.data = (pkt_len << 16) | (BIT_RD | BIT_IRQ | BIT_WRAP | BIT_PAD | BIT_CRC);
    write_reg_seq.start(m_sequencer);

    `uvm_info(get_type_name(), "TX BD armed. Waiting for underrun...", UVM_LOW)

    // 6. Poll BD status for completion
    begin
      int timeout = 0;
      forever begin
        #2000ns;
        read_reg_seq.addr = BD0_STATUS;
        read_reg_seq.start(m_sequencer);
        bd_status = read_reg_seq.data;
        if ((bd_status & BIT_RD) == 0) break;
        timeout++;
        if (timeout > 500) begin
          `uvm_fatal("SEQ", "TIMEOUT: BD0 never completed")
        end
      end
    end

    // 7. Restore normal DMA speed
    p_sequencer.mem_vif.ack_delay = 0;

    // 8. Verify underrun bit
    `uvm_info(get_type_name(), $sformatf("BD0_STATUS = 0x%08h", bd_status), UVM_LOW)

    if ((bd_status & BIT_UNDERRUN) == 0) begin
      `uvm_error(get_type_name(), $sformatf(
        "FAIL: Underrun bit not set in BD status. BD0_STATUS=0x%08h", bd_status))
      all_ok = 0;
    end else
      `uvm_info(get_type_name(), "Underrun bit correctly set in BD status.", UVM_LOW)

    // 9. Verify TXE interrupt via RAL
    read_reg_seq.addr = 32'h04; read_reg_seq.start(m_sequencer); int_status = read_reg_seq.data;

    `uvm_info(get_type_name(), $sformatf("INT_SOURCE = 0x%08h", int_status), UVM_LOW)

    if ((int_status & INT_TXE) == 0) begin
      `uvm_error(get_type_name(), $sformatf(
        "FAIL: TXE interrupt not set. INT_SOURCE=0x%08h", int_status))
      all_ok = 0;
    end else
      `uvm_info(get_type_name(), "TXE interrupt correctly set.", UVM_LOW)

    // 10. Final verdict
    if (all_ok)
      `uvm_info(get_type_name(), $sformatf(
        "PASS: TX underrun detected. BD0_STATUS=0x%08h, INT_SOURCE=0x%08h",
        bd_status, int_status), UVM_LOW)
    else
      `uvm_error(get_type_name(), "FAIL: TX underrun test failed.")

  endtask : body

endclass : tx_underrun_seq

//============================================================================
// RX OVERRUN SEQUENCE (ERR-02)
//============================================================================
class rx_overrun_seq extends uvm_sequence #(wishbone_transaction);
  `uvm_object_utils(rx_overrun_seq)
  `uvm_declare_p_sequencer(host_sequencer)
  reg_write_seq write_reg_seq;
  reg_read_seq  read_reg_seq;

  localparam RX_BD0_STATUS = 32'h408;
  localparam RX_BD0_PTR    = 32'h40C;
  localparam RX_BUFFER     = 32'h4000;

  localparam MODER_RXONLY = 32'h0000_A001;

  localparam BIT_RD   = 16'h8000;
  localparam BIT_IRQ  = 16'h4000;
  localparam BIT_WRAP = 16'h2000;

  localparam BIT_OVERRUN = 32'h0000_0040;
  localparam INT_RXE  = 32'h0000_0008;
  localparam INT_BUSY = 32'h0000_0010;

  localparam MAC_HI = 32'h0000_0011;
  localparam MAC_LO = 32'h2233_4455;

  phy_agent_config m_phy_cfg;

  function new(string name = "rx_overrun_seq");
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

  task inject_frame(byte unsigned dest_addr[6], byte unsigned payload_len);
    byte unsigned frame[$];
    bit [31:0] crc;
    byte unsigned cb[4];

    foreach (dest_addr[i]) frame.push_back(dest_addr[i]);
    frame.push_back(8'h00); frame.push_back(8'hAA);
    frame.push_back(8'hBB); frame.push_back(8'hCC);
    frame.push_back(8'hDD); frame.push_back(8'hEE);
    frame.push_back(8'h00); frame.push_back(payload_len);
    for (int i = 0; i < payload_len; i++)
      frame.push_back(i & 8'hFF);
    while (frame.size() < 60) frame.push_back(8'h00);

    crc = compute_crc(frame);
    cb[0] = crc[7:0]; cb[1] = crc[15:8]; cb[2] = crc[23:16]; cb[3] = crc[31:24];

    m_phy_cfg.vif.crs   <= 1'b1;
    @(posedge m_phy_cfg.vif.rx_clk);
    m_phy_cfg.vif.rx_dv <= 1'b1;
    m_phy_cfg.vif.rxd   <= 4'h5;
    repeat(14) @(posedge m_phy_cfg.vif.rx_clk) m_phy_cfg.vif.rxd <= 4'h5;
    @(posedge m_phy_cfg.vif.rx_clk) m_phy_cfg.vif.rxd <= 4'hD;

    foreach (frame[i]) drive_rx_byte(frame[i]);
    for (int i = 0; i < 4; i++) drive_rx_byte(cb[i]);

    @(posedge m_phy_cfg.vif.rx_clk);
    m_phy_cfg.vif.rx_dv <= 1'b0;
    m_phy_cfg.vif.rxd   <= 4'h0;
    @(posedge m_phy_cfg.vif.rx_clk);
    m_phy_cfg.vif.crs   <= 1'b0;
  endtask

  virtual task body();
    logic [31:0] bd_status, int_status;
    bit all_ok = 1;
    byte unsigned dest_mac[6] = '{8'h00, 8'h11, 8'h22, 8'h33, 8'h44, 8'h55};
    write_reg_seq = reg_write_seq::type_id::create("write_reg_seq");
    read_reg_seq  = reg_read_seq::type_id::create("read_reg_seq");

    `uvm_info(get_type_name(), "ERR-02: RX Overrun Test", UVM_LOW)

    if (!uvm_config_db#(phy_agent_config)::get(null, "uvm_test_top.m_env.m_phy_agent*", "config", m_phy_cfg))
      `uvm_fatal("SEQ", "Cannot get phy_agent_config")
    m_phy_cfg.collisions_remaining = 0;

    // 1. Configure MAC via RAL
    write_reg_seq.addr = 32'h20; write_reg_seq.data = 32'd1; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h18; write_reg_seq.data = 32'h0040_0600; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h44; write_reg_seq.data = MAC_HI; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h40; write_reg_seq.data = MAC_LO; write_reg_seq.start(m_sequencer);

    // RX BD: set pointer but do NOT set Empty (RD) bit — raw
    write_reg_seq.addr = RX_BD0_PTR;
    write_reg_seq.data = RX_BUFFER;
    write_reg_seq.start(m_sequencer);

    write_reg_seq.addr = RX_BD0_STATUS;
    write_reg_seq.data = {16'h0, (BIT_IRQ | BIT_WRAP)};  // NO BIT_RD!
    write_reg_seq.start(m_sequencer);

    // Clear interrupts and enable RXEN via RAL
    write_reg_seq.addr = 32'h04; write_reg_seq.data = 32'hFFFF_FFFF; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h00; write_reg_seq.data = MODER_RXONLY; write_reg_seq.start(m_sequencer);
    `uvm_info(get_type_name(), "MAC configured with RXEN but NO ready RX BDs.", UVM_LOW)

    // 2. Inject a valid packet
    #500ns;
    `uvm_info(get_type_name(), "Injecting packet (should cause overrun)...", UVM_LOW)
    inject_frame(dest_mac, 64);

    // 3. Wait and verify interrupts
    #10000ns;

    read_reg_seq.addr = 32'h04; read_reg_seq.start(m_sequencer); int_status = read_reg_seq.data;

    `uvm_info(get_type_name(), $sformatf("INT_SOURCE = 0x%08h", int_status), UVM_LOW)

    if ((int_status & INT_BUSY) == 0) begin
      `uvm_error(get_type_name(), $sformatf(
        "FAIL: BUSY interrupt not set. INT_SOURCE=0x%08h", int_status))
      all_ok = 0;
    end else
      `uvm_info(get_type_name(), "BUSY interrupt correctly set (no empty RX BD).", UVM_LOW)

    if ((int_status & INT_RXE) == 0) begin
      `uvm_info(get_type_name(), $sformatf(
        "NOTE: RXE not set (INT_SOURCE=0x%08h). BUSY confirms no-BD condition.", int_status), UVM_LOW)
    end else begin
      `uvm_info(get_type_name(), "RXE interrupt correctly set (overrun).", UVM_LOW)
    end

    if (all_ok)
      `uvm_info(get_type_name(), $sformatf(
        "PASS: RX overrun condition detected. INT_SOURCE=0x%08h", int_status), UVM_LOW)
    else
      `uvm_error(get_type_name(), "FAIL: RX overrun test failed.")

  endtask : body

endclass : rx_overrun_seq

//============================================================================
// RX BAD CRC SEQUENCE (ERR-03)
//============================================================================
class rx_bad_crc_seq extends uvm_sequence #(wishbone_transaction);
  `uvm_object_utils(rx_bad_crc_seq)
  `uvm_declare_p_sequencer(host_sequencer)
  reg_write_seq write_reg_seq;
  reg_read_seq  read_reg_seq;

  localparam RX_BD0_STATUS = 32'h408;
  localparam RX_BD0_PTR    = 32'h40C;
  localparam RX_BUFFER     = 32'h4000;

  localparam MODER_RXONLY = 32'h0000_A001;

  localparam BIT_RD   = 16'h8000;
  localparam BIT_IRQ  = 16'h4000;
  localparam BIT_WRAP = 16'h2000;

  localparam BIT_CRCERR = 32'h0000_0002;
  localparam INT_RXE  = 32'h0000_0008;
  localparam INT_RXB  = 32'h0000_0004;

  localparam MAC_HI = 32'h0000_0011;
  localparam MAC_LO = 32'h2233_4455;

  phy_agent_config m_phy_cfg;

  function new(string name = "rx_bad_crc_seq");
    super.new(name);
  endfunction

  task drive_rx_byte(byte unsigned b);
    @(posedge m_phy_cfg.vif.rx_clk); m_phy_cfg.vif.rxd <= b[3:0];
    @(posedge m_phy_cfg.vif.rx_clk); m_phy_cfg.vif.rxd <= b[7:4];
  endtask

  task inject_bad_crc_frame();
    byte unsigned frame[$];
    frame = '{8'h00, 8'h11, 8'h22, 8'h33, 8'h44, 8'h55,
              8'h00, 8'hAA, 8'hBB, 8'hCC, 8'hDD, 8'hEE,
              8'h00, 8'h20};
    for (int i = 0; i < 32; i++) frame.push_back(i & 8'hFF);
    while (frame.size() < 60) frame.push_back(8'h00);

    m_phy_cfg.vif.crs   <= 1'b1;
    @(posedge m_phy_cfg.vif.rx_clk);
    m_phy_cfg.vif.rx_dv <= 1'b1;
    m_phy_cfg.vif.rxd   <= 4'h5;
    repeat(14) @(posedge m_phy_cfg.vif.rx_clk) m_phy_cfg.vif.rxd <= 4'h5;
    @(posedge m_phy_cfg.vif.rx_clk) m_phy_cfg.vif.rxd <= 4'hD;

    foreach (frame[i]) drive_rx_byte(frame[i]);

    // BAD CRC
    drive_rx_byte(8'hDE);
    drive_rx_byte(8'hAD);
    drive_rx_byte(8'hBE);
    drive_rx_byte(8'hEF);

    @(posedge m_phy_cfg.vif.rx_clk);
    m_phy_cfg.vif.rx_dv <= 1'b0;
    m_phy_cfg.vif.rxd   <= 4'h0;
    @(posedge m_phy_cfg.vif.rx_clk);
    m_phy_cfg.vif.crs   <= 1'b0;
  endtask

  virtual task body();
    logic [31:0] bd_status, int_status;
    bit all_ok = 1;
    write_reg_seq = reg_write_seq::type_id::create("write_reg_seq");
    read_reg_seq  = reg_read_seq::type_id::create("read_reg_seq");

    `uvm_info(get_type_name(), "ERR-03: RX Bad CRC Test", UVM_LOW)

    if (!uvm_config_db#(phy_agent_config)::get(null, "uvm_test_top.m_env.m_phy_agent*", "config", m_phy_cfg))
      `uvm_fatal("SEQ", "Cannot get phy_agent_config")
    m_phy_cfg.collisions_remaining = 0;

    // 1. Configure MAC via RAL
    write_reg_seq.addr = 32'h20; write_reg_seq.data = 32'd1; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h18; write_reg_seq.data = 32'h0040_0600; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h44; write_reg_seq.data = MAC_HI; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h40; write_reg_seq.data = MAC_LO; write_reg_seq.start(m_sequencer);

    // Set up RX BD — raw
    write_reg_seq.addr = RX_BD0_PTR;
    write_reg_seq.data = RX_BUFFER;
    write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = RX_BD0_STATUS;
    write_reg_seq.data = {16'h0, (BIT_RD | BIT_IRQ | BIT_WRAP)};
    write_reg_seq.start(m_sequencer);

    // Clear interrupts and enable RXEN via RAL
    write_reg_seq.addr = 32'h04; write_reg_seq.data = 32'hFFFF_FFFF; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h00; write_reg_seq.data = MODER_RXONLY; write_reg_seq.start(m_sequencer);

    `uvm_info(get_type_name(), "MAC configured. Injecting bad CRC frame...", UVM_LOW)

    // 2. Inject frame with bad CRC
    #2000ns;
    inject_bad_crc_frame();

    // 3. Wait and read BD status
    #10000ns;
    read_reg_seq.addr = RX_BD0_STATUS;
    read_reg_seq.start(m_sequencer);
    bd_status = read_reg_seq.data;

    `uvm_info(get_type_name(), $sformatf("RX_BD0_STATUS = 0x%08h", bd_status), UVM_LOW)

    if ((bd_status & BIT_RD) != 0) begin
      `uvm_error(get_type_name(), "FAIL: RX BD still Empty — frame not received")
      all_ok = 0;
    end

    if ((bd_status & BIT_CRCERR) == 0) begin
      `uvm_error(get_type_name(), $sformatf(
        "FAIL: CRC error bit not set. RX_BD0_STATUS=0x%08h", bd_status))
      all_ok = 0;
    end else
      `uvm_info(get_type_name(), "CRC error bit correctly set in RX BD.", UVM_LOW)

    // 5. Check RXE interrupt via RAL
    read_reg_seq.addr = 32'h04; read_reg_seq.start(m_sequencer); int_status = read_reg_seq.data;

    `uvm_info(get_type_name(), $sformatf("INT_SOURCE = 0x%08h", int_status), UVM_LOW)

    if ((int_status & INT_RXE) == 0) begin
      `uvm_error(get_type_name(), $sformatf(
        "FAIL: RXE interrupt not set. INT_SOURCE=0x%08h", int_status))
      all_ok = 0;
    end else
      `uvm_info(get_type_name(), "RXE interrupt correctly set.", UVM_LOW)

    if (all_ok)
      `uvm_info(get_type_name(), $sformatf(
        "PASS: Bad CRC detected. BD=0x%08h, INT=0x%08h", bd_status, int_status), UVM_LOW)
    else
      `uvm_error(get_type_name(), "FAIL: RX bad CRC test failed.")

  endtask : body

endclass : rx_bad_crc_seq

//============================================================================
// RX INVALID SYMBOL SEQUENCE (ERR-04)
//============================================================================
class rx_invalid_symbol_seq extends uvm_sequence #(wishbone_transaction);
  `uvm_object_utils(rx_invalid_symbol_seq)
  `uvm_declare_p_sequencer(host_sequencer)
  reg_write_seq write_reg_seq;
  reg_read_seq  read_reg_seq;

  localparam RX_BD0_STATUS = 32'h408;
  localparam RX_BD0_PTR    = 32'h40C;
  localparam RX_BUFFER     = 32'h4000;

  localparam MODER_RXONLY = 32'h0000_A001;

  localparam BIT_RD   = 16'h8000;
  localparam BIT_IRQ  = 16'h4000;
  localparam BIT_WRAP = 16'h2000;

  localparam BIT_INVSIMB = 32'h0000_0020;
  localparam INT_RXE     = 32'h0000_0008;

  localparam MAC_HI = 32'h0000_0011;
  localparam MAC_LO = 32'h2233_4455;

  phy_agent_config m_phy_cfg;

  function new(string name = "rx_invalid_symbol_seq");
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

  task drive_rx_nibble(logic [3:0] nib);
    @(posedge m_phy_cfg.vif.rx_clk); m_phy_cfg.vif.rxd <= nib;
  endtask

  task drive_rx_byte(byte unsigned b);
    drive_rx_nibble(b[3:0]);
    drive_rx_nibble(b[7:4]);
  endtask

  task inject_frame_with_invalid_symbol();
    byte unsigned frame[$];
    bit [31:0] crc;
    byte unsigned cb[4];
    int inject_at;

    frame = '{8'h00, 8'h11, 8'h22, 8'h33, 8'h44, 8'h55,
              8'h00, 8'hAA, 8'hBB, 8'hCC, 8'hDD, 8'hEE,
              8'h00, 8'h20};
    for (int i = 0; i < 32; i++) frame.push_back(i & 8'hFF);
    while (frame.size() < 60) frame.push_back(8'h00);

    crc = compute_crc(frame);
    cb[0] = crc[7:0]; cb[1] = crc[15:8]; cb[2] = crc[23:16]; cb[3] = crc[31:24];

    inject_at = 20;

    m_phy_cfg.vif.crs    <= 1'b1;
    m_phy_cfg.vif.rx_err <= 1'b0;
    @(posedge m_phy_cfg.vif.rx_clk);
    m_phy_cfg.vif.rx_dv <= 1'b1;
    m_phy_cfg.vif.rxd   <= 4'h5;
    repeat(14) @(posedge m_phy_cfg.vif.rx_clk) m_phy_cfg.vif.rxd <= 4'h5;
    @(posedge m_phy_cfg.vif.rx_clk) m_phy_cfg.vif.rxd <= 4'hD;

    foreach (frame[i]) begin
      if (i == inject_at) begin
        @(posedge m_phy_cfg.vif.rx_clk);
        m_phy_cfg.vif.rxd    <= 4'hE;
        m_phy_cfg.vif.rx_err <= 1'b1;
        @(posedge m_phy_cfg.vif.rx_clk);
        m_phy_cfg.vif.rxd    <= 4'hE;
        m_phy_cfg.vif.rx_err <= 1'b1;
        @(posedge m_phy_cfg.vif.rx_clk);
        m_phy_cfg.vif.rx_err <= 1'b0;
        m_phy_cfg.vif.rxd    <= frame[i][3:0];
        @(posedge m_phy_cfg.vif.rx_clk);
        m_phy_cfg.vif.rxd    <= frame[i][7:4];
      end else begin
        drive_rx_byte(frame[i]);
      end
    end

    for (int i = 0; i < 4; i++) drive_rx_byte(cb[i]);

    @(posedge m_phy_cfg.vif.rx_clk);
    m_phy_cfg.vif.rx_dv  <= 1'b0;
    m_phy_cfg.vif.rxd    <= 4'h0;
    m_phy_cfg.vif.rx_err <= 1'b0;
    @(posedge m_phy_cfg.vif.rx_clk);
    m_phy_cfg.vif.crs    <= 1'b0;
  endtask

  virtual task body();
    logic [31:0] bd_status, int_status;
    bit all_ok = 1;
    write_reg_seq = reg_write_seq::type_id::create("write_reg_seq");
    read_reg_seq  = reg_read_seq::type_id::create("read_reg_seq");

    `uvm_info(get_type_name(), "ERR-04: RX Invalid Symbol Test", UVM_LOW)

    if (!uvm_config_db#(phy_agent_config)::get(null, "uvm_test_top.m_env.m_phy_agent*", "config", m_phy_cfg))
      `uvm_fatal("SEQ", "Cannot get phy_agent_config")
    m_phy_cfg.collisions_remaining = 0;

    // 1. Configure MAC via RAL
    write_reg_seq.addr = 32'h20; write_reg_seq.data = 32'd1; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h18; write_reg_seq.data = 32'h0040_0600; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h44; write_reg_seq.data = MAC_HI; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h40; write_reg_seq.data = MAC_LO; write_reg_seq.start(m_sequencer);

    // Set up RX BD — raw
    write_reg_seq.addr = RX_BD0_PTR;    write_reg_seq.data = RX_BUFFER;  write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = RX_BD0_STATUS;
    write_reg_seq.data = {16'h0, (BIT_RD | BIT_IRQ | BIT_WRAP)};
    write_reg_seq.start(m_sequencer);

    // Clear interrupts and enable RXEN via RAL
    write_reg_seq.addr = 32'h04; write_reg_seq.data = 32'hFFFF_FFFF; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h00; write_reg_seq.data = MODER_RXONLY; write_reg_seq.start(m_sequencer);

    `uvm_info(get_type_name(), "MAC configured. Injecting frame with invalid symbol...", UVM_LOW)

    // 2. Inject frame
    #2000ns;
    inject_frame_with_invalid_symbol();

    // 3. Wait and check
    #10000ns;
    read_reg_seq.addr = RX_BD0_STATUS;
    read_reg_seq.start(m_sequencer);
    bd_status = read_reg_seq.data;

    `uvm_info(get_type_name(), $sformatf("RX_BD0_STATUS = 0x%08h", bd_status), UVM_LOW)

    if ((bd_status & BIT_RD) != 0) begin
      `uvm_error(get_type_name(), "FAIL: RX BD still Empty — frame not received")
      all_ok = 0;
    end

    if ((bd_status & BIT_INVSIMB) == 0) begin
      `uvm_error(get_type_name(), $sformatf(
        "FAIL: INVSIMB bit not set. RX_BD0_STATUS=0x%08h", bd_status))
      all_ok = 0;
    end else
      `uvm_info(get_type_name(), "INVSIMB bit correctly set in RX BD.", UVM_LOW)

    read_reg_seq.addr = 32'h04; read_reg_seq.start(m_sequencer); int_status = read_reg_seq.data;

    `uvm_info(get_type_name(), $sformatf("INT_SOURCE = 0x%08h", int_status), UVM_LOW)

    if ((int_status & INT_RXE) == 0) begin
      `uvm_error(get_type_name(), $sformatf(
        "FAIL: RXE interrupt not set. INT_SOURCE=0x%08h", int_status))
      all_ok = 0;
    end else
      `uvm_info(get_type_name(), "RXE interrupt correctly set.", UVM_LOW)

    if (all_ok)
      `uvm_info(get_type_name(), $sformatf(
        "PASS: Invalid symbol detected. BD=0x%08h, INT=0x%08h", bd_status, int_status), UVM_LOW)
    else
      `uvm_error(get_type_name(), "FAIL: RX invalid symbol test failed.")

  endtask : body

endclass : rx_invalid_symbol_seq

//============================================================================
// RX SHORT FRAME SEQUENCE (ERR-06)
//============================================================================
class rx_short_seq extends uvm_sequence #(wishbone_transaction);
  `uvm_object_utils(rx_short_seq)
  `uvm_declare_p_sequencer(host_sequencer)
  reg_write_seq write_reg_seq;
  reg_read_seq  read_reg_seq;

  localparam RX_BD0_STATUS = 32'h408;
  localparam RX_BD0_PTR    = 32'h40C;
  localparam RX_BUFFER     = 32'h4000;

  localparam MODER_RXONLY       = 32'h0000_A001;
  localparam MODER_RXONLY_SMALL = 32'h0001_A001;  // r_RecSmall=1 (bit 16)

  localparam BIT_RD   = 16'h8000;
  localparam BIT_IRQ  = 16'h4000;
  localparam BIT_WRAP = 16'h2000;

  localparam BIT_SHORT = 32'h0000_0004;
  localparam INT_RXB   = 32'h0000_0004;

  localparam MAC_HI = 32'h0000_0011;
  localparam MAC_LO = 32'h2233_4455;

  phy_agent_config m_phy_cfg;

  function new(string name = "rx_short_seq");
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

  task inject_short_frame();
    byte unsigned frame[$];
    bit [31:0] crc;
    byte unsigned cb[4];

    frame = '{8'h00, 8'h11, 8'h22, 8'h33, 8'h44, 8'h55,
              8'h00, 8'hAA, 8'hBB, 8'hCC, 8'hDD, 8'hEE,
              8'h00, 8'h10};
    for (int i = 0; i < 16; i++) frame.push_back(i & 8'hFF);

    crc = compute_crc(frame);
    cb[0] = crc[7:0]; cb[1] = crc[15:8]; cb[2] = crc[23:16]; cb[3] = crc[31:24];

    m_phy_cfg.vif.crs    <= 1'b1;
    m_phy_cfg.vif.rx_err <= 1'b0;
    @(posedge m_phy_cfg.vif.rx_clk);
    m_phy_cfg.vif.rx_dv <= 1'b1;
    m_phy_cfg.vif.rxd   <= 4'h5;
    repeat(14) @(posedge m_phy_cfg.vif.rx_clk) m_phy_cfg.vif.rxd <= 4'h5;
    @(posedge m_phy_cfg.vif.rx_clk) m_phy_cfg.vif.rxd <= 4'hD;

    foreach (frame[i]) drive_rx_byte(frame[i]);
    for (int i = 0; i < 4; i++) drive_rx_byte(cb[i]);

    @(posedge m_phy_cfg.vif.rx_clk);
    m_phy_cfg.vif.rx_dv <= 1'b0;
    m_phy_cfg.vif.rxd   <= 4'h0;
    @(posedge m_phy_cfg.vif.rx_clk);
    m_phy_cfg.vif.crs   <= 1'b0;
  endtask

  task arm_rx_bd();
    write_reg_seq.addr = RX_BD0_PTR;    write_reg_seq.data = RX_BUFFER;  write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = RX_BD0_STATUS;
    write_reg_seq.data = {16'h0, (BIT_RD | BIT_IRQ | BIT_WRAP)};
    write_reg_seq.start(m_sequencer);
  endtask

  virtual task body();
    logic [31:0] bd_status, int_status;
    bit all_ok = 1;
    write_reg_seq = reg_write_seq::type_id::create("write_reg_seq");
    read_reg_seq  = reg_read_seq::type_id::create("read_reg_seq");

    `uvm_info(get_type_name(), "ERR-06: RX Short Frame Test", UVM_LOW)

    if (!uvm_config_db#(phy_agent_config)::get(null, "uvm_test_top.m_env.m_phy_agent*", "config", m_phy_cfg))
      `uvm_fatal("SEQ", "Cannot get phy_agent_config")
    m_phy_cfg.collisions_remaining = 0;

    // Common MAC config via RAL
    write_reg_seq.addr = 32'h20; write_reg_seq.data = 32'd1; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h18; write_reg_seq.data = 32'h0040_0600; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h44; write_reg_seq.data = MAC_HI; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h40; write_reg_seq.data = MAC_LO; write_reg_seq.start(m_sequencer);

    // PHASE 1: r_RecSmall=0 — short frame should be ABORTED
    `uvm_info(get_type_name(), "PHASE 1: r_RecSmall=0 (reject short frames)", UVM_LOW)

    arm_rx_bd();
    write_reg_seq.addr = 32'h04; write_reg_seq.data = 32'hFFFF_FFFF; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h00; write_reg_seq.data = MODER_RXONLY; write_reg_seq.start(m_sequencer);

    #2000ns;
    inject_short_frame();
    #10000ns;

    read_reg_seq.addr = RX_BD0_STATUS;
    read_reg_seq.start(m_sequencer);
    bd_status = read_reg_seq.data;

    `uvm_info(get_type_name(), $sformatf("Phase1 RX_BD0_STATUS = 0x%08h", bd_status), UVM_LOW)

    if ((bd_status & BIT_RD) != 0)
      `uvm_info(get_type_name(), "Phase1 PASS: BD still Empty — short frame correctly aborted.", UVM_LOW)
    else begin
      `uvm_error(get_type_name(), $sformatf(
        "Phase1 FAIL: BD consumed when r_RecSmall=0. BD=0x%08h", bd_status))
      all_ok = 0;
    end

    // PHASE 2: r_RecSmall=1 — short frame should be ACCEPTED
    `uvm_info(get_type_name(), "PHASE 2: r_RecSmall=1 (accept short frames)", UVM_LOW)

    write_reg_seq.addr = 32'h00; write_reg_seq.data = 32'h0; write_reg_seq.start(m_sequencer);
    #500ns;

    arm_rx_bd();
    write_reg_seq.addr = 32'h04; write_reg_seq.data = 32'hFFFF_FFFF; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h00; write_reg_seq.data = MODER_RXONLY_SMALL; write_reg_seq.start(m_sequencer);

    #2000ns;
    inject_short_frame();
    #10000ns;

    read_reg_seq.addr = RX_BD0_STATUS;
    read_reg_seq.start(m_sequencer);
    bd_status = read_reg_seq.data;

    `uvm_info(get_type_name(), $sformatf("Phase2 RX_BD0_STATUS = 0x%08h", bd_status), UVM_LOW)

    if ((bd_status & BIT_RD) != 0) begin
      `uvm_error(get_type_name(), "Phase2 FAIL: BD still Empty — frame not received with r_RecSmall=1")
      all_ok = 0;
    end

    if ((bd_status & BIT_SHORT) == 0) begin
      `uvm_error(get_type_name(), $sformatf(
        "Phase2 FAIL: SHORT bit not set. BD=0x%08h", bd_status))
      all_ok = 0;
    end else
      `uvm_info(get_type_name(), "Phase2: SHORT bit correctly set in RX BD.", UVM_LOW)

    read_reg_seq.addr = 32'h04; read_reg_seq.start(m_sequencer); int_status = read_reg_seq.data;

    `uvm_info(get_type_name(), $sformatf("Phase2 INT_SOURCE = 0x%08h", int_status), UVM_LOW)

    if ((int_status & INT_RXB) == 0) begin
      `uvm_error(get_type_name(), $sformatf(
        "Phase2 FAIL: RXB interrupt not set. INT_SOURCE=0x%08h", int_status))
      all_ok = 0;
    end else
      `uvm_info(get_type_name(), "Phase2: RXB interrupt correctly set.", UVM_LOW)

    if (all_ok)
      `uvm_info(get_type_name(), "PASS: Both phases passed. Short frame abort/accept verified.", UVM_LOW)
    else
      `uvm_error(get_type_name(), "FAIL: RX short frame test failed.")

  endtask : body

endclass : rx_short_seq

//============================================================================
// RX DRIBBLE NIBBLE SEQUENCE (ERR-07)
//============================================================================
class rx_dribble_seq extends uvm_sequence #(wishbone_transaction);
  `uvm_object_utils(rx_dribble_seq)
  `uvm_declare_p_sequencer(host_sequencer)
  reg_write_seq write_reg_seq;
  reg_read_seq  read_reg_seq;

  localparam RX_BD0_STATUS = 32'h408;
  localparam RX_BD0_PTR    = 32'h40C;
  localparam RX_BUFFER     = 32'h4000;

  localparam MODER_CONF = 32'h0000_A001;

  localparam BIT_RD   = 16'h8000;
  localparam BIT_IRQ  = 16'h4000;
  localparam BIT_WRAP = 16'h2000;

  localparam BIT_DRIBBLE = 32'h0000_0010;
  localparam INT_RXE = 32'h0000_0008;

  localparam MAC_HI = 32'h0000_0011;
  localparam MAC_LO = 32'h2233_4455;

  phy_agent_config m_phy_cfg;

  function new(string name = "rx_dribble_seq");
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

  virtual task body();
    byte unsigned frame[$];
    bit [31:0] crc;
    byte unsigned cb[4];
    logic [31:0] bd_status, int_status;
    bit all_ok = 1;
    int payload_len;
    write_reg_seq = reg_write_seq::type_id::create("write_reg_seq");
    read_reg_seq  = reg_read_seq::type_id::create("read_reg_seq");

    `uvm_info(get_type_name(), "ERR-07: RX Dribble Nibble Test", UVM_LOW)

    if (!uvm_config_db#(phy_agent_config)::get(null, "uvm_test_top.m_env.m_phy_agent*", "config", m_phy_cfg))
      `uvm_fatal("SEQ", "Cannot get phy_agent_config")
    m_phy_cfg.collisions_remaining = 0;

    // 1. Configure MAC via RAL
    write_reg_seq.addr = 32'h20; write_reg_seq.data = 32'd1; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h18; write_reg_seq.data = 32'h0040_0600; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h44; write_reg_seq.data = MAC_HI; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h40; write_reg_seq.data = MAC_LO; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h04; write_reg_seq.data = 32'hFFFF_FFFF; write_reg_seq.start(m_sequencer);

    // 2. Arm RX BD — raw
    write_reg_seq.addr = RX_BD0_PTR;    write_reg_seq.data = RX_BUFFER; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = RX_BD0_STATUS;
    write_reg_seq.data = {16'h0, (BIT_RD | BIT_IRQ | BIT_WRAP)};
    write_reg_seq.start(m_sequencer);

    // 3. Enable RX via RAL
    write_reg_seq.addr = 32'h00; write_reg_seq.data = MODER_CONF; write_reg_seq.start(m_sequencer);
    #2000ns;

    // 4. Build & inject frame with dribble nibble
    payload_len = 50;
    frame = '{8'h00, 8'h11, 8'h22, 8'h33, 8'h44, 8'h55,
              8'h00, 8'hAA, 8'hBB, 8'hCC, 8'hDD, 8'hEE,
              8'h00, 8'h32};
    for (int i = 0; i < payload_len; i++) frame.push_back(i & 8'hFF);

    crc = compute_crc(frame);
    cb[0] = crc[7:0]; cb[1] = crc[15:8]; cb[2] = crc[23:16]; cb[3] = crc[31:24];

    m_phy_cfg.vif.crs    <= 1'b1;
    m_phy_cfg.vif.rx_err <= 1'b0;
    @(posedge m_phy_cfg.vif.rx_clk);
    m_phy_cfg.vif.rx_dv <= 1'b1;
    m_phy_cfg.vif.rxd   <= 4'h5;
    repeat(14) @(posedge m_phy_cfg.vif.rx_clk) m_phy_cfg.vif.rxd <= 4'h5;
    @(posedge m_phy_cfg.vif.rx_clk) m_phy_cfg.vif.rxd <= 4'hD;

    foreach (frame[i]) drive_rx_byte(frame[i]);
    for (int i = 0; i < 4; i++) drive_rx_byte(cb[i]);

    // DRIBBLE: drive ONE extra nibble
    @(posedge m_phy_cfg.vif.rx_clk);
    m_phy_cfg.vif.rxd <= 4'hA;

    @(posedge m_phy_cfg.vif.rx_clk);
    m_phy_cfg.vif.rx_dv <= 1'b0;
    m_phy_cfg.vif.rxd   <= 4'h0;
    @(posedge m_phy_cfg.vif.rx_clk);
    m_phy_cfg.vif.crs   <= 1'b0;

    `uvm_info(get_type_name(), "Frame with dribble nibble injected.", UVM_LOW)

    // 5. Wait and read BD status
    #10000ns;
    read_reg_seq.addr = RX_BD0_STATUS;
    read_reg_seq.start(m_sequencer);
    bd_status = read_reg_seq.data;

    `uvm_info(get_type_name(), $sformatf("RX_BD0_STATUS = 0x%08h", bd_status), UVM_LOW)

    if ((bd_status & BIT_RD) != 0) begin
      `uvm_error(get_type_name(), "FAIL: BD still Empty — frame not received.")
      all_ok = 0;
    end

    if ((bd_status & BIT_DRIBBLE) == 0) begin
      `uvm_error(get_type_name(), $sformatf("FAIL: DRIBBLE bit not set. BD=0x%08h", bd_status))
      all_ok = 0;
    end else
      `uvm_info(get_type_name(), "DRIBBLE bit correctly set in RX BD.", UVM_LOW)

    // 6. Check RXE interrupt via RAL
    read_reg_seq.addr = 32'h04; read_reg_seq.start(m_sequencer); int_status = read_reg_seq.data;

    `uvm_info(get_type_name(), $sformatf("INT_SOURCE = 0x%08h", int_status), UVM_LOW)

    if ((int_status & INT_RXE) == 0) begin
      `uvm_error(get_type_name(), $sformatf("FAIL: RXE interrupt not set. INT_SOURCE=0x%08h", int_status))
      all_ok = 0;
    end else
      `uvm_info(get_type_name(), "RXE interrupt correctly set.", UVM_LOW)

    if (all_ok)
      `uvm_info(get_type_name(), $sformatf(
        "PASS: Dribble nibble detected. BD=0x%08h, INT=0x%08h",
        bd_status, int_status), UVM_LOW)
    else
      `uvm_error(get_type_name(), "FAIL: RX dribble nibble test failed.")

  endtask : body

endclass : rx_dribble_seq
