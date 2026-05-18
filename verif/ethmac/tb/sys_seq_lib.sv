// sys_seq_lib.sv - System-Level Test Sequences using raw Wishbone access

//============================================================================
// LOOPBACK SEQUENCE (SYS-01)
//============================================================================
class loopback_seq extends uvm_sequence #(wishbone_transaction);
  `uvm_object_utils(loopback_seq)
  `uvm_declare_p_sequencer(host_sequencer)
  reg_write_seq write_reg_seq;
  reg_read_seq  read_reg_seq;

  localparam TX_BD0_STATUS = 32'h400;
  localparam TX_BD0_PTR    = 32'h404;
  localparam RX_BD0_STATUS = 32'h408;
  localparam RX_BD0_PTR    = 32'h40C;
  localparam TX_BUFFER  = 32'h2000;
  localparam RX_BUFFER  = 32'h4000;
  localparam MODER_LOOPBACK = 32'h0000_A4A3;
  localparam BIT_RD   = 16'h8000;
  localparam BIT_IRQ  = 16'h4000;
  localparam BIT_WRAP = 16'h2000;
  localparam BIT_PAD  = 16'h1000;
  localparam BIT_CRC  = 16'h0800;
  localparam INT_TXB = 32'h0000_0001;
  localparam INT_RXB = 32'h0000_0004;
  localparam MAC_HI = 32'h0000_0011;
  localparam MAC_LO = 32'h2233_4455;

  function new(string name = "loopback_seq");
    super.new(name);
  endfunction

  virtual task body();
    int pkt_len = 100;
    logic [31:0] tx_bd, rx_bd, int_status;
    bit all_ok = 1;
    int payload_bytes;
    write_reg_seq = reg_write_seq::type_id::create("write_reg_seq");
    read_reg_seq  = reg_read_seq::type_id::create("read_reg_seq");

    `uvm_info(get_type_name(), "SYS-01: Loopback (TX->RX) Test", UVM_LOW)

    // Configure MAC via RAL
    write_reg_seq.addr = 32'h20; write_reg_seq.data = 32'd1; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h0C; write_reg_seq.data = 32'h15; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h18; write_reg_seq.data = 32'h0040_0600; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h44; write_reg_seq.data = MAC_HI; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h40; write_reg_seq.data = MAC_LO; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h04; write_reg_seq.data = 32'hFFFF_FFFF; write_reg_seq.start(m_sequencer);

    // Preload TX buffer via DMA
    begin
      uvm_component comp;
      uvm_sequencer_base dma_seqr;
      reg_write_seq mem_seq;
      byte unsigned frame[$];
      comp = uvm_top.find("uvm_test_top.m_env.m_dma_agent.m_sequencer");
      if (comp == null) `uvm_fatal("SEQ", "Could not find DMA sequencer")
      if (!$cast(dma_seqr, comp)) `uvm_fatal("SEQ", "DMA sequencer cast failed")
      frame = '{8'h00, 8'h11, 8'h22, 8'h33, 8'h44, 8'h55,
                8'h00, 8'hDE, 8'hAD, 8'hBE, 8'hEF, 8'h01,
                8'h00, 8'h56};
      for (int i = 14; i < pkt_len; i++) frame.push_back(i & 8'hFF);
      mem_seq = reg_write_seq::type_id::create("mem_seq");
      for (int i = 0; i < pkt_len; i += 4) begin
        logic [31:0] word = 0;
        for (int b = 0; b < 4 && (i + b) < pkt_len; b++)
          word |= (frame[i + b] << (b * 8));
        mem_seq.addr = TX_BUFFER + i; mem_seq.data = word; mem_seq.start(dma_seqr);
      end
    end

    // Arm RX BD
    write_reg_seq.addr = RX_BD0_PTR;    write_reg_seq.data = RX_BUFFER; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = RX_BD0_STATUS;
    write_reg_seq.data = {16'h0, (BIT_RD | BIT_IRQ | BIT_WRAP)};
    write_reg_seq.start(m_sequencer);

    // Enable loopback via RAL
    write_reg_seq.addr = 32'h00; write_reg_seq.data = MODER_LOOPBACK; write_reg_seq.start(m_sequencer);
    #2000ns;

    // Arm TX BD
    write_reg_seq.addr = TX_BD0_PTR;    write_reg_seq.data = TX_BUFFER; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = TX_BD0_STATUS;
    write_reg_seq.data = (pkt_len << 16) | (BIT_RD | BIT_IRQ | BIT_WRAP | BIT_PAD | BIT_CRC);
    write_reg_seq.start(m_sequencer);

    `uvm_info(get_type_name(), "TX launched in loopback mode.", UVM_LOW)

    // Poll TX BD
    for (int i = 0; i < 5000; i++) begin
      #1000ns;
      read_reg_seq.addr = TX_BD0_STATUS; read_reg_seq.start(m_sequencer);
      tx_bd = read_reg_seq.data;
      if ((tx_bd & BIT_RD) == 0) break;
    end
    if ((tx_bd & BIT_RD) != 0) begin `uvm_error(get_type_name(), "TIMEOUT: TX BD") all_ok = 0; end

    #5000ns;
    read_reg_seq.addr = RX_BD0_STATUS; read_reg_seq.start(m_sequencer);
    rx_bd = read_reg_seq.data;
    if ((rx_bd & BIT_RD) != 0) begin `uvm_error(get_type_name(), "FAIL: RX BD still Empty") all_ok = 0; end

    // Check interrupts via RAL
    read_reg_seq.addr = 32'h04; read_reg_seq.start(m_sequencer); int_status = read_reg_seq.data;
    if ((int_status & INT_TXB) == 0) begin `uvm_error(get_type_name(), "FAIL: TXB not set") all_ok = 0; end
    if ((int_status & INT_RXB) == 0) begin `uvm_error(get_type_name(), "FAIL: RXB not set") all_ok = 0; end

    if ((rx_bd & BIT_RD) == 0) begin
      payload_bytes = (rx_bd >> 16) & 16'hFFFF;
      if (payload_bytes != pkt_len + 4) begin
        `uvm_error(get_type_name(), $sformatf("FAIL: RX length %0d != %0d", payload_bytes, pkt_len + 4))
        all_ok = 0;
      end
    end

    if (all_ok)
      `uvm_info(get_type_name(), $sformatf("PASS: Loopback verified. TX=0x%08h RX=0x%08h INT=0x%08h", tx_bd, rx_bd, int_status), UVM_LOW)
    else
      `uvm_error(get_type_name(), "FAIL: Loopback test failed.")
  endtask : body
endclass : loopback_seq

//============================================================================
// INTERRUPT SEQUENCE (SYS-02)
//============================================================================
class interrupt_seq extends uvm_sequence #(wishbone_transaction);
  `uvm_object_utils(interrupt_seq)
  `uvm_declare_p_sequencer(host_sequencer)
  reg_write_seq write_reg_seq;
  reg_read_seq  read_reg_seq;

  localparam TX_BD0_STATUS = 32'h400;
  localparam TX_BD0_PTR    = 32'h404;
  localparam RX_BD0_STATUS = 32'h408;
  localparam RX_BD0_PTR    = 32'h40C;
  localparam TX_BUFFER  = 32'h2000;
  localparam RX_BUFFER  = 32'h4000;
  localparam MODER_FD_PRO = 32'h0000_A023;
  localparam BIT_RD   = 16'h8000;
  localparam BIT_IRQ  = 16'h4000;
  localparam BIT_WRAP = 16'h2000;
  localparam BIT_PAD  = 16'h1000;
  localparam BIT_CRC  = 16'h0800;
  localparam INT_TXB  = 32'h01;
  localparam INT_TXE  = 32'h02;
  localparam INT_RXB  = 32'h04;
  localparam INT_RXE  = 32'h08;
  localparam INT_BUSY = 32'h10;
  localparam MAC_HI = 32'h0000_0011;
  localparam MAC_LO = 32'h2233_4455;

  host_agent_config m_host_cfg;
  phy_agent_config  m_phy_cfg;

  function new(string name = "interrupt_seq");
    super.new(name);
  endfunction

  function automatic bit [31:0] compute_crc(byte unsigned data[$]);
    bit [31:0] crc = 32'hFFFFFFFF;
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

  task inject_rx_frame(bit bad_crc = 0);
    byte unsigned frame[$];
    bit [31:0] crc;
    byte unsigned cb[4];
    frame = '{8'h00, 8'h11, 8'h22, 8'h33, 8'h44, 8'h55,
              8'h00, 8'hAA, 8'hBB, 8'hCC, 8'hDD, 8'hEE,
              8'h00, 8'h32};
    for (int i = 0; i < 50; i++) frame.push_back(i & 8'hFF);
    crc = compute_crc(frame);
    if (bad_crc) crc = ~crc;
    cb[0] = crc[7:0]; cb[1] = crc[15:8]; cb[2] = crc[23:16]; cb[3] = crc[31:24];
    m_phy_cfg.vif.crs <= 1'b1; m_phy_cfg.vif.rx_err <= 1'b0;
    @(posedge m_phy_cfg.vif.rx_clk);
    m_phy_cfg.vif.rx_dv <= 1'b1; m_phy_cfg.vif.rxd <= 4'h5;
    repeat(14) @(posedge m_phy_cfg.vif.rx_clk) m_phy_cfg.vif.rxd <= 4'h5;
    @(posedge m_phy_cfg.vif.rx_clk) m_phy_cfg.vif.rxd <= 4'hD;
    foreach (frame[i]) drive_rx_byte(frame[i]);
    for (int i = 0; i < 4; i++) drive_rx_byte(cb[i]);
    @(posedge m_phy_cfg.vif.rx_clk);
    m_phy_cfg.vif.rx_dv <= 1'b0; m_phy_cfg.vif.rxd <= 4'h0;
    @(posedge m_phy_cfg.vif.rx_clk);
    m_phy_cfg.vif.crs <= 1'b0;
  endtask

  task check_int_o(string phase, bit expected, output bit pass);
    #100ns;
    pass = 1;
    if (m_host_cfg.mem_vif.int_o !== expected) begin
      `uvm_error(get_type_name(), $sformatf("%s: int_o=%0b, expected %0b", phase, m_host_cfg.mem_vif.int_o, expected))
      pass = 0;
    end else
      `uvm_info(get_type_name(), $sformatf("%s: int_o=%0b OK", phase, m_host_cfg.mem_vif.int_o), UVM_LOW)
  endtask

  task reset_phase();
    write_reg_seq.addr = 32'h00; write_reg_seq.data = 32'h0; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h04; write_reg_seq.data = 32'hFFFF_FFFF; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h08; write_reg_seq.data = 32'h0; write_reg_seq.start(m_sequencer);
    #500ns;
  endtask

  task mac_setup();
    write_reg_seq.addr = 32'h20; write_reg_seq.data = 32'd1; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h18; write_reg_seq.data = 32'h0040_0600; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h44; write_reg_seq.data = MAC_HI; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h40; write_reg_seq.data = MAC_LO; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h04; write_reg_seq.data = 32'hFFFF_FFFF; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h08; write_reg_seq.data = 32'h7F; write_reg_seq.start(m_sequencer);
  endtask

  virtual task body();
    logic [31:0] int_src;
    bit all_ok = 1;
    bit phase_ok;
    write_reg_seq = reg_write_seq::type_id::create("write_reg_seq");
    read_reg_seq  = reg_read_seq::type_id::create("read_reg_seq");

    `uvm_info(get_type_name(), "SYS-02: Interrupt Verification Test", UVM_LOW)

    if (!uvm_config_db#(host_agent_config)::get(null, "uvm_test_top.m_env.m_host_agent*", "config", m_host_cfg))
      `uvm_fatal("SEQ", "Cannot get host_agent_config")
    if (!uvm_config_db#(phy_agent_config)::get(null, "uvm_test_top.m_env.m_phy_agent*", "config", m_phy_cfg))
      `uvm_fatal("SEQ", "Cannot get phy_agent_config")
    m_phy_cfg.collisions_remaining = 0;

    // ---- PHASE 1: TXB ----
    `uvm_info(get_type_name(), "=== PHASE 1: TXB ===", UVM_LOW)
    mac_setup();
    write_reg_seq.addr = 32'h0C; write_reg_seq.data = 32'h15; write_reg_seq.start(m_sequencer);
    begin
      uvm_component comp; uvm_sequencer_base dma_seqr; reg_write_seq mem_seq;
      comp = uvm_top.find("uvm_test_top.m_env.m_dma_agent.m_sequencer");
      if (!$cast(dma_seqr, comp)) `uvm_fatal("SEQ", "DMA sequencer cast failed")
      mem_seq = reg_write_seq::type_id::create("mem_seq");
      for (int i = 0; i < 64; i += 4) begin
        mem_seq.addr = TX_BUFFER + i; mem_seq.data = {8'(i+3), 8'(i+2), 8'(i+1), 8'(i)}; mem_seq.start(dma_seqr);
      end
    end
    write_reg_seq.addr = 32'h00; write_reg_seq.data = 32'hA003; write_reg_seq.start(m_sequencer);
    #500ns;
    write_reg_seq.addr = TX_BD0_PTR; write_reg_seq.data = TX_BUFFER; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = TX_BD0_STATUS;
    write_reg_seq.data = (64 << 16) | (BIT_RD | BIT_IRQ | BIT_WRAP | BIT_PAD | BIT_CRC);
    write_reg_seq.start(m_sequencer);
    for (int i = 0; i < 500; i++) begin
      #100ns; read_reg_seq.addr = TX_BD0_STATUS; read_reg_seq.start(m_sequencer);
      if ((read_reg_seq.data & BIT_RD) == 0) break;
    end
    #2000ns;
    read_reg_seq.addr = 32'h04; read_reg_seq.start(m_sequencer); int_src = read_reg_seq.data;
    `uvm_info(get_type_name(), $sformatf("P1 INT_SOURCE=0x%08h", int_src), UVM_LOW)
    if (!(int_src & INT_TXB)) begin `uvm_error(get_type_name(), "FAIL: TXB not set") all_ok=0; end
    else `uvm_info(get_type_name(), "TXB set.", UVM_LOW)
    phase_ok=1; check_int_o("P1 mask=ON", 1'b1, phase_ok); if(!phase_ok) all_ok=0;
    write_reg_seq.addr = 32'h04; write_reg_seq.data = INT_TXB; write_reg_seq.start(m_sequencer);
    read_reg_seq.addr = 32'h04; read_reg_seq.start(m_sequencer); int_src = read_reg_seq.data;
    if (int_src & INT_TXB) begin `uvm_error(get_type_name(), "FAIL: TXB W1C failed") all_ok=0; end
    else `uvm_info(get_type_name(), "TXB W1C OK.", UVM_LOW)
    phase_ok=1; check_int_o("P1 W1C", 1'b0, phase_ok); if(!phase_ok) all_ok=0;

    // ---- PHASE 2: RXB ----
    `uvm_info(get_type_name(), "=== PHASE 2: RXB ===", UVM_LOW)
    reset_phase(); mac_setup();
    write_reg_seq.addr = RX_BD0_PTR; write_reg_seq.data = RX_BUFFER; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = RX_BD0_STATUS;
    write_reg_seq.data = {16'h0, (BIT_RD | BIT_IRQ | BIT_WRAP)};
    write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h00; write_reg_seq.data = MODER_FD_PRO; write_reg_seq.start(m_sequencer);
    #2000ns;
    inject_rx_frame();
    #10000ns;
    read_reg_seq.addr = 32'h04; read_reg_seq.start(m_sequencer); int_src = read_reg_seq.data;
    `uvm_info(get_type_name(), $sformatf("P2 INT_SOURCE=0x%08h", int_src), UVM_LOW)
    if (!(int_src & INT_RXB)) begin `uvm_error(get_type_name(), "FAIL: RXB not set") all_ok=0; end
    else `uvm_info(get_type_name(), "RXB set.", UVM_LOW)
    phase_ok=1; check_int_o("P2 mask=ON", 1'b1, phase_ok); if(!phase_ok) all_ok=0;
    write_reg_seq.addr = 32'h08; write_reg_seq.data = 32'h0; write_reg_seq.start(m_sequencer);
    phase_ok=1; check_int_o("P2 mask=OFF", 1'b0, phase_ok); if(!phase_ok) all_ok=0;
    write_reg_seq.addr = 32'h08; write_reg_seq.data = INT_RXB; write_reg_seq.start(m_sequencer);
    phase_ok=1; check_int_o("P2 mask=RXB", 1'b1, phase_ok); if(!phase_ok) all_ok=0;
    write_reg_seq.addr = 32'h04; write_reg_seq.data = INT_RXB; write_reg_seq.start(m_sequencer);
    phase_ok=1; check_int_o("P2 W1C", 1'b0, phase_ok); if(!phase_ok) all_ok=0;

    // ---- PHASE 3: BUSY ----
    `uvm_info(get_type_name(), "=== PHASE 3: BUSY ===", UVM_LOW)
    reset_phase(); mac_setup();
    write_reg_seq.addr = RX_BD0_PTR; write_reg_seq.data = RX_BUFFER; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = RX_BD0_STATUS;
    write_reg_seq.data = {16'h0, (BIT_IRQ | BIT_WRAP)};
    write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h00; write_reg_seq.data = MODER_FD_PRO; write_reg_seq.start(m_sequencer);
    #2000ns;
    inject_rx_frame();
    #10000ns;
    read_reg_seq.addr = 32'h04; read_reg_seq.start(m_sequencer); int_src = read_reg_seq.data;
    `uvm_info(get_type_name(), $sformatf("P3 INT_SOURCE=0x%08h", int_src), UVM_LOW)
    if (!(int_src & INT_BUSY)) begin `uvm_error(get_type_name(), "FAIL: BUSY not set") all_ok=0; end
    else `uvm_info(get_type_name(), "BUSY set.", UVM_LOW)
    phase_ok=1; check_int_o("P3 mask=ON", 1'b1, phase_ok); if(!phase_ok) all_ok=0;
    write_reg_seq.addr = 32'h04; write_reg_seq.data = INT_BUSY; write_reg_seq.start(m_sequencer);
    read_reg_seq.addr = 32'h04; read_reg_seq.start(m_sequencer); int_src = read_reg_seq.data;
    if (int_src & INT_BUSY) begin `uvm_error(get_type_name(), "FAIL: BUSY W1C failed") all_ok=0; end
    else `uvm_info(get_type_name(), "BUSY W1C OK.", UVM_LOW)

    // ---- PHASE 4: RXE ----
    `uvm_info(get_type_name(), "=== PHASE 4: RXE ===", UVM_LOW)
    reset_phase(); mac_setup();
    write_reg_seq.addr = RX_BD0_PTR; write_reg_seq.data = RX_BUFFER; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = RX_BD0_STATUS;
    write_reg_seq.data = {16'h0, (BIT_RD | BIT_IRQ | BIT_WRAP)};
    write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h00; write_reg_seq.data = MODER_FD_PRO; write_reg_seq.start(m_sequencer);
    #2000ns;
    inject_rx_frame(.bad_crc(1));
    #10000ns;
    read_reg_seq.addr = 32'h04; read_reg_seq.start(m_sequencer); int_src = read_reg_seq.data;
    `uvm_info(get_type_name(), $sformatf("P4 INT_SOURCE=0x%08h", int_src), UVM_LOW)
    if (!(int_src & INT_RXE)) begin `uvm_error(get_type_name(), "FAIL: RXE not set") all_ok=0; end
    else `uvm_info(get_type_name(), "RXE set.", UVM_LOW)
    phase_ok=1; check_int_o("P4 mask=ON", 1'b1, phase_ok); if(!phase_ok) all_ok=0;
    write_reg_seq.addr = 32'h04; write_reg_seq.data = INT_RXE; write_reg_seq.start(m_sequencer);

    // ---- PHASE 5: TXE ----
    `uvm_info(get_type_name(), "=== PHASE 5: TXE ===", UVM_LOW)
    reset_phase(); mac_setup();
    write_reg_seq.addr = 32'h0C; write_reg_seq.data = 32'h15; write_reg_seq.start(m_sequencer);
    begin
      uvm_component comp; uvm_sequencer_base dma_seqr; reg_write_seq mem_seq;
      comp = uvm_top.find("uvm_test_top.m_env.m_dma_agent.m_sequencer");
      if (!$cast(dma_seqr, comp)) `uvm_fatal("SEQ", "DMA sequencer cast failed")
      mem_seq = reg_write_seq::type_id::create("mem_seq");
      for (int i = 0; i < 1500; i += 4) begin
        mem_seq.addr = TX_BUFFER + i; mem_seq.data = {8'(i+3), 8'(i+2), 8'(i+1), 8'(i)}; mem_seq.start(dma_seqr);
      end
    end
    write_reg_seq.addr = 32'h00; write_reg_seq.data = 32'hA003; write_reg_seq.start(m_sequencer);
    #500ns;
    m_host_cfg.mem_vif.ack_delay = 200;
    write_reg_seq.addr = TX_BD0_PTR; write_reg_seq.data = TX_BUFFER; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = TX_BD0_STATUS;
    write_reg_seq.data = (1500 << 16) | (BIT_RD | BIT_IRQ | BIT_WRAP | BIT_PAD | BIT_CRC);
    write_reg_seq.start(m_sequencer);
    for (int i = 0; i < 500; i++) begin
      #100ns; read_reg_seq.addr = TX_BD0_STATUS; read_reg_seq.start(m_sequencer);
      if ((read_reg_seq.data & BIT_RD) == 0) break;
    end
    #2000ns;
    m_host_cfg.mem_vif.ack_delay = 0;
    read_reg_seq.addr = 32'h04; read_reg_seq.start(m_sequencer); int_src = read_reg_seq.data;
    `uvm_info(get_type_name(), $sformatf("P5 INT_SOURCE=0x%08h", int_src), UVM_LOW)
    if (!(int_src & INT_TXE)) begin `uvm_error(get_type_name(), "FAIL: TXE not set") all_ok=0; end
    else `uvm_info(get_type_name(), "TXE set.", UVM_LOW)
    phase_ok=1; check_int_o("P5 mask=ON", 1'b1, phase_ok); if(!phase_ok) all_ok=0;
    write_reg_seq.addr = 32'h04; write_reg_seq.data = 32'hFFFF_FFFF; write_reg_seq.start(m_sequencer);

    // ---- PHASE 6: INT_MASK read-back ----
    `uvm_info(get_type_name(), "=== PHASE 6: INT_MASK Read-Back ===", UVM_LOW)
    begin
      logic [31:0] mask_val;
      for (int bit_i = 0; bit_i < 7; bit_i++) begin
        write_reg_seq.addr = 32'h08; write_reg_seq.data = (1 << bit_i); write_reg_seq.start(m_sequencer);
        read_reg_seq.addr = 32'h08; read_reg_seq.start(m_sequencer); mask_val = read_reg_seq.data;
        if (mask_val != (1 << bit_i)) begin
          `uvm_error(get_type_name(), $sformatf("FAIL: INT_MASK mismatch bit %0d", bit_i))
          all_ok = 0;
        end
      end
      `uvm_info(get_type_name(), "INT_MASK read-back OK for all 7 bits.", UVM_LOW)
    end

    if (all_ok)
      `uvm_info(get_type_name(), "PASS: All interrupts verified.", UVM_LOW)
    else
      `uvm_error(get_type_name(), "FAIL: Interrupt verification failed.")
  endtask : body
endclass : interrupt_seq

//============================================================================
// SPEED MODE SEQUENCE (SYS-03)
//============================================================================
class speed_mode_seq extends uvm_sequence #(wishbone_transaction);
  `uvm_object_utils(speed_mode_seq)
  `uvm_declare_p_sequencer(host_sequencer)
  reg_write_seq write_reg_seq;
  reg_read_seq  read_reg_seq;

  localparam TX_BD0_STATUS = 32'h400;
  localparam TX_BD0_PTR    = 32'h404;
  localparam RX_BD0_STATUS = 32'h408;
  localparam RX_BD0_PTR    = 32'h40C;
  localparam TX_BUFFER  = 32'h2000;
  localparam RX_BUFFER  = 32'h4000;
  localparam MODER_FD_PRO = 32'h0000_A023;
  localparam BIT_RD   = 16'h8000;
  localparam BIT_IRQ  = 16'h4000;
  localparam BIT_WRAP = 16'h2000;
  localparam BIT_PAD  = 16'h1000;
  localparam BIT_CRC  = 16'h0800;
  localparam MAC_HI = 32'h0000_0011;
  localparam MAC_LO = 32'h2233_4455;

  host_agent_config m_host_cfg;
  phy_agent_config  m_phy_cfg;

  function new(string name = "speed_mode_seq");
    super.new(name);
  endfunction

  function automatic bit [31:0] compute_crc(byte unsigned data[$]);
    bit [31:0] crc = 32'hFFFFFFFF;
    foreach (data[i]) begin crc = crc ^ data[i]; repeat (8) begin if (crc[0]) crc = (crc >> 1) ^ 32'hEDB88320; else crc = (crc >> 1); end end
    return ~crc;
  endfunction

  task drive_rx_byte(byte unsigned b);
    @(posedge m_phy_cfg.vif.rx_clk); m_phy_cfg.vif.rxd <= b[3:0];
    @(posedge m_phy_cfg.vif.rx_clk); m_phy_cfg.vif.rxd <= b[7:4];
  endtask

  task inject_rx_frame();
    byte unsigned frame[$]; bit [31:0] crc; byte unsigned cb[4];
    frame = '{8'h00, 8'h11, 8'h22, 8'h33, 8'h44, 8'h55, 8'h00, 8'hAA, 8'hBB, 8'hCC, 8'hDD, 8'hEE, 8'h00, 8'h32};
    for (int i = 0; i < 50; i++) frame.push_back(i & 8'hFF);
    crc = compute_crc(frame);
    cb[0] = crc[7:0]; cb[1] = crc[15:8]; cb[2] = crc[23:16]; cb[3] = crc[31:24];
    m_phy_cfg.vif.crs <= 1'b1; m_phy_cfg.vif.rx_err <= 1'b0;
    @(posedge m_phy_cfg.vif.rx_clk);
    m_phy_cfg.vif.rx_dv <= 1'b1; m_phy_cfg.vif.rxd <= 4'h5;
    repeat(14) @(posedge m_phy_cfg.vif.rx_clk) m_phy_cfg.vif.rxd <= 4'h5;
    @(posedge m_phy_cfg.vif.rx_clk) m_phy_cfg.vif.rxd <= 4'hD;
    foreach (frame[i]) drive_rx_byte(frame[i]);
    for (int i = 0; i < 4; i++) drive_rx_byte(cb[i]);
    @(posedge m_phy_cfg.vif.rx_clk);
    m_phy_cfg.vif.rx_dv <= 1'b0; m_phy_cfg.vif.rxd <= 4'h0;
    @(posedge m_phy_cfg.vif.rx_clk);
    m_phy_cfg.vif.crs <= 1'b0;
  endtask

  task set_speed(int speed_mbps);
    if (speed_mbps == 10) begin
      m_phy_cfg.vif.mii_tx_half_period = 200;
      m_phy_cfg.vif.mii_rx_half_period = 200;
    end else begin
      m_phy_cfg.vif.mii_tx_half_period = 20;
      m_phy_cfg.vif.mii_rx_half_period = 20;
    end
    `uvm_info(get_type_name(), $sformatf("MII clock set to %0d Mbps", speed_mbps), UVM_LOW)
    #500ns;
  endtask

  task do_tx_rx_test(string phase_name, output bit pass);
    logic [31:0] bd_status, int_src;
    pass = 1;
    write_reg_seq.addr = 32'h00; write_reg_seq.data = 32'h0; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h04; write_reg_seq.data = 32'hFFFF_FFFF; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h08; write_reg_seq.data = 32'h7F; write_reg_seq.start(m_sequencer);
    #500ns;
    write_reg_seq.addr = 32'h20; write_reg_seq.data = 32'd1; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h0C; write_reg_seq.data = 32'h15; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h18; write_reg_seq.data = 32'h0040_0600; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h44; write_reg_seq.data = MAC_HI; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h40; write_reg_seq.data = MAC_LO; write_reg_seq.start(m_sequencer);
    begin
      uvm_component comp; uvm_sequencer_base dma_seqr; reg_write_seq mem_seq;
      comp = uvm_top.find("uvm_test_top.m_env.m_dma_agent.m_sequencer");
      if (!$cast(dma_seqr, comp)) `uvm_fatal("SEQ", "DMA sequencer cast failed")
      mem_seq = reg_write_seq::type_id::create("mem_seq");
      for (int i = 0; i < 64; i += 4) begin
        mem_seq.addr = TX_BUFFER + i; mem_seq.data = {8'(i+3), 8'(i+2), 8'(i+1), 8'(i)}; mem_seq.start(dma_seqr);
      end
    end
    write_reg_seq.addr = 32'h00; write_reg_seq.data = MODER_FD_PRO; write_reg_seq.start(m_sequencer);
    #500ns;
    // TX
    write_reg_seq.addr = TX_BD0_PTR; write_reg_seq.data = TX_BUFFER; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = TX_BD0_STATUS;
    write_reg_seq.data = (64 << 16) | (BIT_RD | BIT_IRQ | BIT_WRAP | BIT_PAD | BIT_CRC);
    write_reg_seq.start(m_sequencer);
    for (int i = 0; i < 5000; i++) begin
      #100ns; read_reg_seq.addr = TX_BD0_STATUS; read_reg_seq.start(m_sequencer);
      if ((read_reg_seq.data & BIT_RD) == 0) break;
    end
    bd_status = read_reg_seq.data;
    `uvm_info(get_type_name(), $sformatf("%s TX BD=0x%08h", phase_name, bd_status), UVM_LOW)
    if (bd_status & BIT_RD) begin `uvm_error(get_type_name(), $sformatf("%s TX timeout!", phase_name)) pass = 0; return; end
    read_reg_seq.addr = 32'h04; read_reg_seq.start(m_sequencer); int_src = read_reg_seq.data;
    if (!(int_src & 32'h01)) begin `uvm_error(get_type_name(), $sformatf("%s TX: TXB not set", phase_name)) pass = 0; end
    else `uvm_info(get_type_name(), $sformatf("%s TX OK", phase_name), UVM_LOW)
    write_reg_seq.addr = 32'h04; write_reg_seq.data = 32'hFFFF_FFFF; write_reg_seq.start(m_sequencer);
    #2000ns;
    // RX
    write_reg_seq.addr = RX_BD0_PTR; write_reg_seq.data = RX_BUFFER; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = RX_BD0_STATUS;
    write_reg_seq.data = {16'h0, (BIT_RD | BIT_IRQ | BIT_WRAP)};
    write_reg_seq.start(m_sequencer);
    inject_rx_frame();
    for (int i = 0; i < 5000; i++) begin
      #200ns; read_reg_seq.addr = RX_BD0_STATUS; read_reg_seq.start(m_sequencer);
      if ((read_reg_seq.data & BIT_RD) == 0) break;
    end
    bd_status = read_reg_seq.data;
    `uvm_info(get_type_name(), $sformatf("%s RX BD=0x%08h", phase_name, bd_status), UVM_LOW)
    if (bd_status & BIT_RD) begin `uvm_error(get_type_name(), $sformatf("%s RX timeout!", phase_name)) pass = 0; return; end
    read_reg_seq.addr = 32'h04; read_reg_seq.start(m_sequencer); int_src = read_reg_seq.data;
    if (!(int_src & 32'h04)) begin `uvm_error(get_type_name(), $sformatf("%s RX: RXB not set", phase_name)) pass = 0; end
    else `uvm_info(get_type_name(), $sformatf("%s RX OK", phase_name), UVM_LOW)
    write_reg_seq.addr = 32'h04; write_reg_seq.data = 32'hFFFF_FFFF; write_reg_seq.start(m_sequencer);
  endtask

  virtual task body();
    bit all_ok = 1; bit phase_ok;
    write_reg_seq = reg_write_seq::type_id::create("write_reg_seq");
    read_reg_seq  = reg_read_seq::type_id::create("read_reg_seq");

    `uvm_info(get_type_name(), "SYS-03: Speed Mode Test (10/100 Mbps)", UVM_LOW)

    if (!uvm_config_db#(host_agent_config)::get(null, "uvm_test_top.m_env.m_host_agent*", "config", m_host_cfg))
      `uvm_fatal("SEQ", "Cannot get host_agent_config")
    if (!uvm_config_db#(phy_agent_config)::get(null, "uvm_test_top.m_env.m_phy_agent*", "config", m_phy_cfg))
      `uvm_fatal("SEQ", "Cannot get phy_agent_config")
    m_phy_cfg.collisions_remaining = 0;

    `uvm_info(get_type_name(), "=== Phase 1: 100 Mbps ===", UVM_LOW)
    set_speed(100); do_tx_rx_test("100M", phase_ok); if (!phase_ok) all_ok = 0;
    `uvm_info(get_type_name(), "=== Phase 2: 10 Mbps ===", UVM_LOW)
    set_speed(10); do_tx_rx_test("10M", phase_ok); if (!phase_ok) all_ok = 0;
    `uvm_info(get_type_name(), "=== Phase 3: 100 Mbps (switch-back) ===", UVM_LOW)
    set_speed(100); do_tx_rx_test("100M_2", phase_ok); if (!phase_ok) all_ok = 0;

    if (all_ok) `uvm_info(get_type_name(), "PASS: 10/100 Mbps speed mode test OK.", UVM_LOW)
    else `uvm_error(get_type_name(), "FAIL: Speed mode test failed.")
  endtask : body
endclass : speed_mode_seq

//============================================================================
// RANDOM TRAFFIC SEQUENCE (SYS-04)
//============================================================================
class rand_traffic_seq extends uvm_sequence #(wishbone_transaction);
  `uvm_object_utils(rand_traffic_seq)
  `uvm_declare_p_sequencer(host_sequencer)
  reg_write_seq write_reg_seq;
  reg_read_seq  read_reg_seq;

  localparam TX_BD0_STATUS = 32'h400;
  localparam TX_BD0_PTR    = 32'h404;
  localparam RX_BD0_STATUS = 32'h408;
  localparam RX_BD0_PTR    = 32'h40C;
  localparam TX_BUFFER  = 32'h2000;
  localparam RX_BUFFER  = 32'h4000;
  localparam BIT_RD   = 16'h8000;
  localparam BIT_IRQ  = 16'h4000;
  localparam BIT_WRAP = 16'h2000;
  localparam BIT_PAD  = 16'h1000;
  localparam BIT_CRC  = 16'h0800;
  localparam MAC_HI = 32'h0000_0011;
  localparam MAC_LO = 32'h2233_4455;
  localparam N_ROUNDS = 20;
  typedef enum {ERR_NONE, ERR_BAD_CRC, ERR_SHORT, ERR_DRIBBLE} err_t;

  host_agent_config m_host_cfg;
  phy_agent_config  m_phy_cfg;

  function new(string name = "rand_traffic_seq");
    super.new(name);
  endfunction

  function automatic bit [31:0] compute_crc(byte unsigned data[$]);
    bit [31:0] crc = 32'hFFFFFFFF;
    foreach (data[i]) begin crc = crc ^ data[i]; repeat (8) begin if (crc[0]) crc = (crc >> 1) ^ 32'hEDB88320; else crc = (crc >> 1); end end
    return ~crc;
  endfunction

  task drive_rx_byte(byte unsigned b);
    @(posedge m_phy_cfg.vif.rx_clk); m_phy_cfg.vif.rxd <= b[3:0];
    @(posedge m_phy_cfg.vif.rx_clk); m_phy_cfg.vif.rxd <= b[7:4];
  endtask

  task inject_rx_frame(int payload_len, bit bad_crc, bit dribble);
    byte unsigned frame[$]; bit [31:0] crc; byte unsigned cb[4];
    frame = '{8'h00, 8'h11, 8'h22, 8'h33, 8'h44, 8'h55, 8'h00, 8'hAA, 8'hBB, 8'hCC, 8'hDD, 8'hEE, 8'h00, 8'h10};
    for (int i = 0; i < payload_len; i++) frame.push_back(i & 8'hFF);
    crc = compute_crc(frame);
    if (bad_crc) crc = ~crc;
    cb[0] = crc[7:0]; cb[1] = crc[15:8]; cb[2] = crc[23:16]; cb[3] = crc[31:24];
    m_phy_cfg.vif.crs <= 1'b1; m_phy_cfg.vif.rx_err <= 1'b0;
    @(posedge m_phy_cfg.vif.rx_clk);
    m_phy_cfg.vif.rx_dv <= 1'b1; m_phy_cfg.vif.rxd <= 4'h5;
    repeat(14) @(posedge m_phy_cfg.vif.rx_clk) m_phy_cfg.vif.rxd <= 4'h5;
    @(posedge m_phy_cfg.vif.rx_clk) m_phy_cfg.vif.rxd <= 4'hD;
    foreach (frame[i]) drive_rx_byte(frame[i]);
    for (int i = 0; i < 4; i++) drive_rx_byte(cb[i]);
    if (dribble) begin @(posedge m_phy_cfg.vif.rx_clk); m_phy_cfg.vif.rxd <= 4'hA; end
    @(posedge m_phy_cfg.vif.rx_clk);
    m_phy_cfg.vif.rx_dv <= 1'b0; m_phy_cfg.vif.rxd <= 4'h0;
    @(posedge m_phy_cfg.vif.rx_clk);
    m_phy_cfg.vif.crs <= 1'b0;
  endtask

  virtual task body();
    int pass_count = 0, fail_count = 0;
    int total_tx = 0, total_rx = 0;
    int total_err_none = 0, total_err_crc = 0, total_err_short = 0, total_err_drib = 0;
    int unsigned seed;
    bit do_tx; err_t err_type; int frame_size;
    bit full_duplex, promiscuous;
    logic [31:0] moder_val, bd_status, int_src;
    bit round_ok;
    write_reg_seq = reg_write_seq::type_id::create("write_reg_seq");
    read_reg_seq  = reg_read_seq::type_id::create("read_reg_seq");

    `uvm_info(get_type_name(), $sformatf("SYS-04: Random Traffic Test (%0d rounds)", N_ROUNDS), UVM_LOW)

    if (!uvm_config_db#(host_agent_config)::get(null, "uvm_test_top.m_env.m_host_agent*", "config", m_host_cfg))
      `uvm_fatal("SEQ", "Cannot get host_agent_config")
    if (!uvm_config_db#(phy_agent_config)::get(null, "uvm_test_top.m_env.m_phy_agent*", "config", m_phy_cfg))
      `uvm_fatal("SEQ", "Cannot get phy_agent_config")
    m_phy_cfg.collisions_remaining = 0;
    seed = $urandom;

    for (int rnd = 0; rnd < N_ROUNDS; rnd++) begin
      round_ok = 1;
      do_tx = $urandom_range(0, 1); full_duplex = $urandom_range(0, 1); promiscuous = 1;
      if (do_tx) begin err_type = ERR_NONE; frame_size = $urandom_range(64, 1500); total_tx++; end
      else begin
        case ($urandom_range(0, 3)) 0: err_type = ERR_NONE; 1: err_type = ERR_BAD_CRC; 2: err_type = ERR_SHORT; 3: err_type = ERR_DRIBBLE; endcase
        if (err_type == ERR_SHORT) frame_size = $urandom_range(20, 45); else frame_size = $urandom_range(46, 800);
        total_rx++;
      end
      case (err_type) ERR_NONE: total_err_none++; ERR_BAD_CRC: total_err_crc++; ERR_SHORT: total_err_short++; ERR_DRIBBLE: total_err_drib++; endcase

      // Setup MAC via RAL
      write_reg_seq.addr = 32'h00; write_reg_seq.data = 32'h0; write_reg_seq.start(m_sequencer);
      write_reg_seq.addr = 32'h04; write_reg_seq.data = 32'hFFFF_FFFF; write_reg_seq.start(m_sequencer);
      write_reg_seq.addr = 32'h08; write_reg_seq.data = 32'h7F; write_reg_seq.start(m_sequencer);
      #200ns;
      write_reg_seq.addr = 32'h20; write_reg_seq.data = 32'd1; write_reg_seq.start(m_sequencer);
      write_reg_seq.addr = 32'h0C; write_reg_seq.data = 32'h15; write_reg_seq.start(m_sequencer);
      write_reg_seq.addr = 32'h18; write_reg_seq.data = 32'h0040_0600; write_reg_seq.start(m_sequencer);
      write_reg_seq.addr = 32'h44; write_reg_seq.data = MAC_HI; write_reg_seq.start(m_sequencer);
      write_reg_seq.addr = 32'h40; write_reg_seq.data = MAC_LO; write_reg_seq.start(m_sequencer);

      moder_val = 32'h0000_2803;
      if (full_duplex) moder_val = moder_val | 32'h0000_0400;
      if (promiscuous) moder_val = moder_val | 32'h0000_0020;
      if (err_type == ERR_SHORT) moder_val = moder_val | 32'h0001_0000;
      write_reg_seq.addr = 32'h00; write_reg_seq.data = moder_val; write_reg_seq.start(m_sequencer);
      #500ns;

      `uvm_info(get_type_name(), $sformatf("Round %0d: %s %s size=%0d err=%s MODER=0x%08h",
        rnd, do_tx ? "TX" : "RX", full_duplex ? "FD" : "HD", frame_size, err_type.name(), moder_val), UVM_LOW)

      if (do_tx) begin
        begin
          uvm_component comp; uvm_sequencer_base dma_seqr; reg_write_seq mem_seq;
          comp = uvm_top.find("uvm_test_top.m_env.m_dma_agent.m_sequencer");
          if (!$cast(dma_seqr, comp)) `uvm_fatal("SEQ", "DMA sequencer cast failed")
          mem_seq = reg_write_seq::type_id::create("mem_seq");
          for (int i = 0; i < frame_size; i += 4) begin
            mem_seq.addr = TX_BUFFER + i; mem_seq.data = {8'(i+3), 8'(i+2), 8'(i+1), 8'(i)}; mem_seq.start(dma_seqr);
          end
        end
        write_reg_seq.addr = TX_BD0_PTR; write_reg_seq.data = TX_BUFFER; write_reg_seq.start(m_sequencer);
        write_reg_seq.addr = TX_BD0_STATUS;
        write_reg_seq.data = (frame_size << 16) | (BIT_RD | BIT_IRQ | BIT_WRAP | BIT_PAD | BIT_CRC);
        write_reg_seq.start(m_sequencer);
        for (int i = 0; i < 5000; i++) begin
          #100ns; read_reg_seq.addr = TX_BD0_STATUS; read_reg_seq.start(m_sequencer);
          if ((read_reg_seq.data & BIT_RD) == 0) break;
        end
        bd_status = read_reg_seq.data;
        if (bd_status & BIT_RD) begin `uvm_error(get_type_name(), $sformatf("Round %0d TX timeout!", rnd)) round_ok = 0; end
        else begin
          read_reg_seq.addr = 32'h04; read_reg_seq.start(m_sequencer); int_src = read_reg_seq.data;
          if (!(int_src & 32'h01)) begin `uvm_error(get_type_name(), $sformatf("Round %0d TX: TXB not set", rnd)) round_ok = 0; end
        end
      end else begin
        write_reg_seq.addr = RX_BD0_PTR; write_reg_seq.data = RX_BUFFER; write_reg_seq.start(m_sequencer);
        write_reg_seq.addr = RX_BD0_STATUS;
        write_reg_seq.data = {16'h0, (BIT_RD | BIT_IRQ | BIT_WRAP)};
        write_reg_seq.start(m_sequencer);
        inject_rx_frame(.payload_len(frame_size), .bad_crc(err_type == ERR_BAD_CRC), .dribble(err_type == ERR_DRIBBLE));
        for (int i = 0; i < 5000; i++) begin
          #200ns; read_reg_seq.addr = RX_BD0_STATUS; read_reg_seq.start(m_sequencer);
          if ((read_reg_seq.data & BIT_RD) == 0) break;
        end
        bd_status = read_reg_seq.data;
        if (bd_status & BIT_RD) begin `uvm_error(get_type_name(), $sformatf("Round %0d RX timeout!", rnd)) round_ok = 0; end
        else begin
          read_reg_seq.addr = 32'h04; read_reg_seq.start(m_sequencer); int_src = read_reg_seq.data;
          case (err_type)
            ERR_NONE: begin if (!(int_src & 32'h04)) begin `uvm_error(get_type_name(), $sformatf("Round %0d: RXB not set", rnd)) round_ok=0; end end
            ERR_BAD_CRC: begin if (!(int_src & 32'h08)) begin `uvm_error(get_type_name(), $sformatf("Round %0d: RXE not set", rnd)) round_ok=0; end
              if (!(bd_status & 32'h02)) begin `uvm_error(get_type_name(), $sformatf("Round %0d: CRC bit not set", rnd)) round_ok=0; end end
            ERR_SHORT: begin if (!(bd_status & 32'h04)) begin `uvm_error(get_type_name(), $sformatf("Round %0d: SHORT not set", rnd)) round_ok=0; end end
            ERR_DRIBBLE: begin if (!(int_src & 32'h08)) begin `uvm_error(get_type_name(), $sformatf("Round %0d: RXE not set", rnd)) round_ok=0; end
              if (!(bd_status & 32'h10)) begin `uvm_error(get_type_name(), $sformatf("Round %0d: DRIBBLE not set", rnd)) round_ok=0; end end
          endcase
        end
      end
      if (round_ok) begin pass_count++; `uvm_info(get_type_name(), $sformatf("Round %0d: PASS", rnd), UVM_LOW) end
      else fail_count++;
      #1000ns;
    end
    `uvm_info(get_type_name(), $sformatf("=== SUMMARY: %0d/%0d passed | TX=%0d RX=%0d ===", pass_count, N_ROUNDS, total_tx, total_rx), UVM_LOW)
    if (fail_count == 0) `uvm_info(get_type_name(), "PASS: All random traffic rounds passed.", UVM_LOW)
    else `uvm_error(get_type_name(), $sformatf("FAIL: %0d/%0d rounds failed.", fail_count, N_ROUNDS))
  endtask : body
endclass : rand_traffic_seq

//============================================================================
// THROUGHPUT SEQUENCE (SYS-05)
//============================================================================
class throughput_seq extends uvm_sequence #(wishbone_transaction);
  `uvm_object_utils(throughput_seq)
  `uvm_declare_p_sequencer(host_sequencer)
  reg_write_seq write_reg_seq;
  reg_read_seq  read_reg_seq;

  localparam BD_BASE    = 32'h400;
  localparam TX_BUFFER  = 32'h2000;
  localparam RX_BUFFER  = 32'h8000;
  localparam BIT_RD   = 16'h8000;
  localparam BIT_IRQ  = 16'h4000;
  localparam BIT_WRAP = 16'h2000;
  localparam BIT_PAD  = 16'h1000;
  localparam BIT_CRC  = 16'h0800;
  localparam MAC_HI = 32'h0000_0011;
  localparam MAC_LO = 32'h2233_4455;
  localparam N_PKT       = 8;
  localparam PKT_SIZE    = 1500;
  localparam PKT_BUF_GAP = 32'h0800;

  host_agent_config m_host_cfg;
  phy_agent_config  m_phy_cfg;

  function new(string name = "throughput_seq");
    super.new(name);
  endfunction

  function automatic bit [31:0] compute_crc(byte unsigned data[$]);
    bit [31:0] crc = 32'hFFFFFFFF;
    foreach (data[i]) begin crc = crc ^ data[i]; repeat (8) begin if (crc[0]) crc = (crc >> 1) ^ 32'hEDB88320; else crc = (crc >> 1); end end
    return ~crc;
  endfunction

  task drive_rx_byte(byte unsigned b);
    @(posedge m_phy_cfg.vif.rx_clk); m_phy_cfg.vif.rxd <= b[3:0];
    @(posedge m_phy_cfg.vif.rx_clk); m_phy_cfg.vif.rxd <= b[7:4];
  endtask

  task inject_rx_frame(int pkt_id);
    byte unsigned frame[$]; bit [31:0] crc; byte unsigned cb[4];
    frame = '{8'h00, 8'h11, 8'h22, 8'h33, 8'h44, 8'h55, 8'h00, 8'hAA, 8'hBB, 8'hCC, 8'hDD, 8'hEE, 8'(pkt_id), 8'h00};
    for (int i = 0; i < (PKT_SIZE - 14); i++) frame.push_back((i + pkt_id) & 8'hFF);
    crc = compute_crc(frame);
    cb[0] = crc[7:0]; cb[1] = crc[15:8]; cb[2] = crc[23:16]; cb[3] = crc[31:24];
    m_phy_cfg.vif.crs <= 1'b1; m_phy_cfg.vif.rx_err <= 1'b0;
    @(posedge m_phy_cfg.vif.rx_clk);
    m_phy_cfg.vif.rx_dv <= 1'b1; m_phy_cfg.vif.rxd <= 4'h5;
    repeat(14) @(posedge m_phy_cfg.vif.rx_clk) m_phy_cfg.vif.rxd <= 4'h5;
    @(posedge m_phy_cfg.vif.rx_clk) m_phy_cfg.vif.rxd <= 4'hD;
    foreach (frame[i]) drive_rx_byte(frame[i]);
    for (int i = 0; i < 4; i++) drive_rx_byte(cb[i]);
    @(posedge m_phy_cfg.vif.rx_clk);
    m_phy_cfg.vif.rx_dv <= 1'b0; m_phy_cfg.vif.rxd <= 4'h0;
    @(posedge m_phy_cfg.vif.rx_clk);
    m_phy_cfg.vif.crs <= 1'b0;
  endtask

  virtual task body();
    bit all_ok = 1;
    logic [31:0] bd_status, int_src;
    time t_start, t_end, t_elapsed;
    real tx_bits, rx_bits, tx_mbps, rx_mbps;
    int tx_done_count, rx_done_count;
    write_reg_seq = reg_write_seq::type_id::create("write_reg_seq");
    read_reg_seq  = reg_read_seq::type_id::create("read_reg_seq");

    `uvm_info(get_type_name(), $sformatf("SYS-05: Throughput Test - %0dx%0dB", N_PKT, PKT_SIZE), UVM_LOW)

    if (!uvm_config_db#(host_agent_config)::get(null, "uvm_test_top.m_env.m_host_agent*", "config", m_host_cfg))
      `uvm_fatal("SEQ", "Cannot get host_agent_config")
    if (!uvm_config_db#(phy_agent_config)::get(null, "uvm_test_top.m_env.m_phy_agent*", "config", m_phy_cfg))
      `uvm_fatal("SEQ", "Cannot get phy_agent_config")
    m_phy_cfg.collisions_remaining = 0;

    // Reset & configure via RAL
    write_reg_seq.addr = 32'h00; write_reg_seq.data = 32'h0; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h04; write_reg_seq.data = 32'hFFFF_FFFF; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h08; write_reg_seq.data = 32'h7F; write_reg_seq.start(m_sequencer);
    #200ns;
    write_reg_seq.addr = 32'h20; write_reg_seq.data = N_PKT; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h0C; write_reg_seq.data = 32'h15; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h18; write_reg_seq.data = 32'h0040_0600; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h44; write_reg_seq.data = MAC_HI; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h40; write_reg_seq.data = MAC_LO; write_reg_seq.start(m_sequencer);

    // Preload TX data
    begin
      uvm_component comp; uvm_sequencer_base dma_seqr; reg_write_seq mem_seq;
      comp = uvm_top.find("uvm_test_top.m_env.m_dma_agent.m_sequencer");
      if (!$cast(dma_seqr, comp)) `uvm_fatal("SEQ", "DMA sequencer cast failed")
      mem_seq = reg_write_seq::type_id::create("mem_seq");
      for (int p = 0; p < N_PKT; p++)
        for (int i = 0; i < PKT_SIZE; i += 4) begin
          mem_seq.addr = TX_BUFFER + p * PKT_BUF_GAP + i;
          mem_seq.data = {8'(i+3+p), 8'(i+2+p), 8'(i+1+p), 8'(i+p)};
          mem_seq.start(dma_seqr);
        end
    end

    // Program TX BDs
    for (int i = 0; i < N_PKT; i++) begin
      logic [31:0] tx_bd_addr; logic [15:0] flags;
      tx_bd_addr = BD_BASE + i * 8;
      flags = BIT_RD | BIT_IRQ | BIT_PAD | BIT_CRC;
      if (i == N_PKT-1) flags = flags | BIT_WRAP;
      write_reg_seq.addr = tx_bd_addr + 4; write_reg_seq.data = TX_BUFFER + i * PKT_BUF_GAP; write_reg_seq.start(m_sequencer);
      write_reg_seq.addr = tx_bd_addr; write_reg_seq.data = (PKT_SIZE << 16) | flags; write_reg_seq.start(m_sequencer);
    end

    // Program RX BDs
    for (int i = 0; i < N_PKT; i++) begin
      logic [31:0] rx_bd_addr; logic [15:0] flags;
      rx_bd_addr = BD_BASE + (N_PKT + i) * 8;
      flags = BIT_RD | BIT_IRQ;
      if (i == N_PKT-1) flags = flags | BIT_WRAP;
      write_reg_seq.addr = rx_bd_addr + 4; write_reg_seq.data = RX_BUFFER + i * PKT_BUF_GAP; write_reg_seq.start(m_sequencer);
      write_reg_seq.addr = rx_bd_addr; write_reg_seq.data = {16'h0, flags}; write_reg_seq.start(m_sequencer);
    end

    // Enable MAC via RAL
    write_reg_seq.addr = 32'h00; write_reg_seq.data = 32'h0000_A823; write_reg_seq.start(m_sequencer);
    #500ns;

    t_start = $time;
    fork
      begin
        for (int p = 0; p < N_PKT; p++) begin
          inject_rx_frame(p);
          repeat(24) @(posedge m_phy_cfg.vif.rx_clk);
        end
      end
    join_none

    // Wait TX complete
    for (int attempt = 0; attempt < 50000; attempt++) begin
      #100ns; read_reg_seq.addr = BD_BASE + (N_PKT-1) * 8; read_reg_seq.start(m_sequencer);
      if ((read_reg_seq.data & BIT_RD) == 0) break;
    end

    tx_done_count = 0;
    for (int i = 0; i < N_PKT; i++) begin
      read_reg_seq.addr = BD_BASE + i * 8; read_reg_seq.start(m_sequencer);
      if ((read_reg_seq.data & BIT_RD) == 0) tx_done_count++;
    end
    if (tx_done_count != N_PKT) begin `uvm_error(get_type_name(), $sformatf("TX incomplete: %0d/%0d", tx_done_count, N_PKT)) all_ok = 0; end
    t_end = $time;

    // Wait RX complete
    for (int attempt = 0; attempt < 50000; attempt++) begin
      #100ns; read_reg_seq.addr = BD_BASE + (N_PKT + N_PKT - 1) * 8; read_reg_seq.start(m_sequencer);
      if ((read_reg_seq.data & BIT_RD) == 0) break;
    end

    rx_done_count = 0;
    for (int i = 0; i < N_PKT; i++) begin
      read_reg_seq.addr = BD_BASE + (N_PKT + i) * 8; read_reg_seq.start(m_sequencer);
      if ((read_reg_seq.data & BIT_RD) == 0) rx_done_count++;
    end
    if (rx_done_count < N_PKT - 2) begin `uvm_error(get_type_name(), $sformatf("RX too many drops: %0d/%0d", rx_done_count, N_PKT)) all_ok = 0; end

    t_elapsed = t_end - t_start;
    tx_bits = N_PKT * (PKT_SIZE + 12) * 8;
    rx_bits = rx_done_count * (PKT_SIZE + 12) * 8;
    if (t_elapsed > 0) begin tx_mbps = tx_bits / (t_elapsed / 1.0) * 1000.0; rx_mbps = rx_bits / (t_elapsed / 1.0) * 1000.0; end

    `uvm_info(get_type_name(), $sformatf("TX: %0d pkts, RX: %0d pkts, Elapsed: %0t", N_PKT, rx_done_count, t_elapsed), UVM_LOW)

    read_reg_seq.addr = 32'h04; read_reg_seq.start(m_sequencer); int_src = read_reg_seq.data;
    if (!(int_src & 32'h01)) begin `uvm_error(get_type_name(), "TXB not set") all_ok = 0; end
    write_reg_seq.addr = 32'h04; write_reg_seq.data = 32'hFFFF_FFFF; write_reg_seq.start(m_sequencer);

    if (all_ok) `uvm_info(get_type_name(), "PASS: Throughput test completed.", UVM_LOW)
    else `uvm_error(get_type_name(), "FAIL: Throughput test failed.")
  endtask : body
endclass : throughput_seq

//============================================================================
// BD WRAP SEQUENCE (SYS-06)
//============================================================================
class bd_wrap_seq extends uvm_sequence #(wishbone_transaction);
  `uvm_object_utils(bd_wrap_seq)
  `uvm_declare_p_sequencer(host_sequencer)
  reg_write_seq write_reg_seq;
  reg_read_seq  read_reg_seq;

  localparam BD_BASE    = 32'h400;
  localparam TX_BUFFER0 = 32'h2000;
  localparam TX_BUFFER1 = 32'h2800;
  localparam RX_BUFFER0 = 32'h4000;
  localparam RX_BUFFER1 = 32'h4800;
  localparam BIT_RD   = 16'h8000;
  localparam BIT_IRQ  = 16'h4000;
  localparam BIT_WRAP = 16'h2000;
  localparam BIT_PAD  = 16'h1000;
  localparam BIT_CRC  = 16'h0800;
  localparam MAC_HI = 32'h0000_0011;
  localparam MAC_LO = 32'h2233_4455;
  localparam N_TX_BDS  = 2;
  localparam N_WRAPS   = 4;
  localparam PKT_SIZE  = 64;

  host_agent_config m_host_cfg;
  phy_agent_config  m_phy_cfg;

  function new(string name = "bd_wrap_seq");
    super.new(name);
  endfunction

  function automatic bit [31:0] compute_crc(byte unsigned data[$]);
    bit [31:0] crc = 32'hFFFFFFFF;
    foreach (data[i]) begin crc = crc ^ data[i]; repeat (8) begin if (crc[0]) crc = (crc >> 1) ^ 32'hEDB88320; else crc = (crc >> 1); end end
    return ~crc;
  endfunction

  task drive_rx_byte(byte unsigned b);
    @(posedge m_phy_cfg.vif.rx_clk); m_phy_cfg.vif.rxd <= b[3:0];
    @(posedge m_phy_cfg.vif.rx_clk); m_phy_cfg.vif.rxd <= b[7:4];
  endtask

  task inject_rx_frame(int pkt_id);
    byte unsigned frame[$]; bit [31:0] crc; byte unsigned cb[4]; int payload_len;
    payload_len = PKT_SIZE - 14;
    frame = '{8'h00, 8'h11, 8'h22, 8'h33, 8'h44, 8'h55, 8'h00, 8'hAA, 8'hBB, 8'hCC, 8'hDD, 8'hEE, 8'(pkt_id), 8'h00};
    for (int i = 0; i < payload_len; i++) frame.push_back((i + pkt_id) & 8'hFF);
    crc = compute_crc(frame);
    cb[0] = crc[7:0]; cb[1] = crc[15:8]; cb[2] = crc[23:16]; cb[3] = crc[31:24];
    m_phy_cfg.vif.crs <= 1'b1; m_phy_cfg.vif.rx_err <= 1'b0;
    @(posedge m_phy_cfg.vif.rx_clk);
    m_phy_cfg.vif.rx_dv <= 1'b1; m_phy_cfg.vif.rxd <= 4'h5;
    repeat(14) @(posedge m_phy_cfg.vif.rx_clk) m_phy_cfg.vif.rxd <= 4'h5;
    @(posedge m_phy_cfg.vif.rx_clk) m_phy_cfg.vif.rxd <= 4'hD;
    foreach (frame[i]) drive_rx_byte(frame[i]);
    for (int i = 0; i < 4; i++) drive_rx_byte(cb[i]);
    @(posedge m_phy_cfg.vif.rx_clk);
    m_phy_cfg.vif.rx_dv <= 1'b0; m_phy_cfg.vif.rxd <= 4'h0;
    @(posedge m_phy_cfg.vif.rx_clk);
    m_phy_cfg.vif.crs <= 1'b0;
  endtask

  virtual task body();
    bit all_ok = 1;
    logic [31:0] bd_status, int_src;
    logic [31:0] tx_bd_addr, rx_bd_addr;
    logic [15:0] flags;
    int bd_idx;
    write_reg_seq = reg_write_seq::type_id::create("write_reg_seq");
    read_reg_seq  = reg_read_seq::type_id::create("read_reg_seq");

    `uvm_info(get_type_name(), $sformatf("SYS-06: BD Wrap Test - %0d BDs, %0d pkts", N_TX_BDS, N_WRAPS), UVM_LOW)

    if (!uvm_config_db#(host_agent_config)::get(null, "uvm_test_top.m_env.m_host_agent*", "config", m_host_cfg))
      `uvm_fatal("SEQ", "Cannot get host_agent_config")
    if (!uvm_config_db#(phy_agent_config)::get(null, "uvm_test_top.m_env.m_phy_agent*", "config", m_phy_cfg))
      `uvm_fatal("SEQ", "Cannot get phy_agent_config")
    m_phy_cfg.collisions_remaining = 0;

    // Reset & configure via RAL
    write_reg_seq.addr = 32'h00; write_reg_seq.data = 32'h0; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h04; write_reg_seq.data = 32'hFFFF_FFFF; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h08; write_reg_seq.data = 32'h7F; write_reg_seq.start(m_sequencer);
    #200ns;
    write_reg_seq.addr = 32'h20; write_reg_seq.data = N_TX_BDS; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h0C; write_reg_seq.data = 32'h15; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h18; write_reg_seq.data = 32'h0040_0600; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h44; write_reg_seq.data = MAC_HI; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h40; write_reg_seq.data = MAC_LO; write_reg_seq.start(m_sequencer);

    // Preload TX buffers
    begin
      uvm_component comp; uvm_sequencer_base dma_seqr; reg_write_seq mem_seq;
      comp = uvm_top.find("uvm_test_top.m_env.m_dma_agent.m_sequencer");
      if (!$cast(dma_seqr, comp)) `uvm_fatal("SEQ", "DMA sequencer cast failed")
      mem_seq = reg_write_seq::type_id::create("mem_seq");
      for (int i = 0; i < PKT_SIZE; i += 4) begin
        mem_seq.addr = TX_BUFFER0 + i; mem_seq.data = {8'(i+3), 8'(i+2), 8'(i+1), 8'(i)}; mem_seq.start(dma_seqr);
      end
      for (int i = 0; i < PKT_SIZE; i += 4) begin
        mem_seq.addr = TX_BUFFER1 + i; mem_seq.data = {8'(i+7), 8'(i+6), 8'(i+5), 8'(i+4)}; mem_seq.start(dma_seqr);
      end
    end

    // Setup BD pointers
    write_reg_seq.addr = BD_BASE + 4; write_reg_seq.data = TX_BUFFER0; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = BD_BASE + 8 + 4; write_reg_seq.data = TX_BUFFER1; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = BD_BASE + N_TX_BDS * 8 + 4; write_reg_seq.data = RX_BUFFER0; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = BD_BASE + (N_TX_BDS + 1) * 8 + 4; write_reg_seq.data = RX_BUFFER1; write_reg_seq.start(m_sequencer);

    // Enable MAC via RAL
    write_reg_seq.addr = 32'h00; write_reg_seq.data = 32'h0000_A823; write_reg_seq.start(m_sequencer);
    #500ns;

    // PHASE 1: TX WRAP
    `uvm_info(get_type_name(), "--- Phase 1: TX BD Wrap ---", UVM_LOW)
    for (int pkt = 0; pkt < N_WRAPS; pkt++) begin
      bd_idx = pkt % N_TX_BDS;
      tx_bd_addr = BD_BASE + bd_idx * 8;
      flags = BIT_RD | BIT_IRQ | BIT_PAD | BIT_CRC;
      if (bd_idx == N_TX_BDS - 1) flags = flags | BIT_WRAP;
      write_reg_seq.addr = 32'h04; write_reg_seq.data = 32'hFFFF_FFFF; write_reg_seq.start(m_sequencer);
      write_reg_seq.addr = tx_bd_addr;
      write_reg_seq.data = (PKT_SIZE << 16) | flags;
      write_reg_seq.start(m_sequencer);
      for (int w = 0; w < 5000; w++) begin
        #100ns; read_reg_seq.addr = tx_bd_addr; read_reg_seq.start(m_sequencer);
        if ((read_reg_seq.data & BIT_RD) == 0) break;
      end
      bd_status = read_reg_seq.data;
      if (bd_status & BIT_RD) begin `uvm_error(get_type_name(), $sformatf("TX pkt %0d timeout!", pkt)) all_ok = 0; end
      else if (bd_status & 32'h010D) begin `uvm_error(get_type_name(), $sformatf("TX pkt %0d error: 0x%08h", pkt, bd_status)) all_ok = 0; end
      else begin
        read_reg_seq.addr = 32'h04; read_reg_seq.start(m_sequencer); int_src = read_reg_seq.data;
        if (!(int_src & 32'h01)) begin `uvm_error(get_type_name(), $sformatf("TX pkt %0d: TXB not set", pkt)) all_ok = 0; end
        else `uvm_info(get_type_name(), $sformatf("TX pkt %0d (BD[%0d]): PASS", pkt, bd_idx), UVM_LOW)
      end
      #500ns;
    end

    // PHASE 2: RX WRAP
    `uvm_info(get_type_name(), "--- Phase 2: RX BD Wrap ---", UVM_LOW)
    for (int pkt = 0; pkt < N_WRAPS; pkt++) begin
      bd_idx = pkt % N_TX_BDS;
      rx_bd_addr = BD_BASE + (N_TX_BDS + bd_idx) * 8;
      flags = BIT_RD | BIT_IRQ;
      if (bd_idx == N_TX_BDS - 1) flags = flags | BIT_WRAP;
      write_reg_seq.addr = 32'h04; write_reg_seq.data = 32'hFFFF_FFFF; write_reg_seq.start(m_sequencer);
      write_reg_seq.addr = rx_bd_addr;
      write_reg_seq.data = {16'h0, flags};
      write_reg_seq.start(m_sequencer);
      inject_rx_frame(pkt);
      for (int w = 0; w < 5000; w++) begin
        #200ns; read_reg_seq.addr = rx_bd_addr; read_reg_seq.start(m_sequencer);
        if ((read_reg_seq.data & BIT_RD) == 0) break;
      end
      bd_status = read_reg_seq.data;
      if (bd_status & BIT_RD) begin `uvm_error(get_type_name(), $sformatf("RX pkt %0d timeout!", pkt)) all_ok = 0; end
      else if (bd_status & 32'h007F) begin `uvm_error(get_type_name(), $sformatf("RX pkt %0d error: 0x%08h", pkt, bd_status)) all_ok = 0; end
      else begin
        read_reg_seq.addr = 32'h04; read_reg_seq.start(m_sequencer); int_src = read_reg_seq.data;
        if (!(int_src & 32'h04)) begin `uvm_error(get_type_name(), $sformatf("RX pkt %0d: RXB not set", pkt)) all_ok = 0; end
        else `uvm_info(get_type_name(), $sformatf("RX pkt %0d (BD[%0d]): PASS", pkt, bd_idx), UVM_LOW)
      end
      #500ns;
    end

    if (all_ok) `uvm_info(get_type_name(), $sformatf("PASS: BD wrap test OK - %0d TX + %0d RX.", N_WRAPS, N_WRAPS), UVM_LOW)
    else `uvm_error(get_type_name(), "FAIL: BD wrap test failed.")
  endtask : body
endclass : bd_wrap_seq
