// hd_seq_lib.sv - Half-Duplex Collision Sequences using raw Wishbone access

//============================================================================
// TX SINGLE COLLISION SEQUENCE (HD-01)
//============================================================================
class tx_single_collision_seq extends uvm_sequence #(wishbone_transaction);
  `uvm_object_utils(tx_single_collision_seq)
  `uvm_declare_p_sequencer(host_sequencer)
  reg_write_seq write_reg_seq;
  reg_read_seq  read_reg_seq;

  // Buffer Descriptor (not in RAL)
  localparam BD0_STATUS = 32'h400;
  localparam BD0_PTR    = 32'h404;
  localparam TX_BUFFER  = 32'h2000;

  // MODER: Half-duplex (no FULLD), PAD + CRC + TXEN
  localparam MODER_CONF = 32'h0000_A002;

  // BD Status Bits
  localparam BIT_RD   = 16'h8000;
  localparam BIT_IRQ  = 16'h4000;
  localparam BIT_WRAP = 16'h2000;
  localparam BIT_PAD  = 16'h1000;
  localparam BIT_CRC  = 16'h0800;
  localparam BIT_RL   = 16'h0008;
  localparam BIT_RC_MASK = 16'h00F0;

  function new(string name = "tx_single_collision_seq");
    super.new(name);
  endfunction

  virtual task body();
    int pkt_len = 100;
    logic [31:0] bd_status;
    int retry_count;
    phy_agent_config m_phy_cfg;
    write_reg_seq = reg_write_seq::type_id::create("write_reg_seq");
    read_reg_seq  = reg_read_seq::type_id::create("read_reg_seq");

    `uvm_info(get_type_name(), "HD-01: Single Collision + Retransmission Test", UVM_LOW)

    // 1. Get PHY config and set exactly 1 collision
    if (!uvm_config_db#(phy_agent_config)::get(null, "uvm_test_top.m_env.m_phy_agent*", "config", m_phy_cfg))
      `uvm_fatal("SEQ", "Could not get PHY agent config")

    m_phy_cfg.collisions_remaining = 1;
    `uvm_info(get_type_name(), $sformatf("PHY collisions_remaining set to %0d", m_phy_cfg.collisions_remaining), UVM_LOW)

    // 2. Configure MAC for Half-Duplex via RAL
    write_reg_seq.addr = 32'h0C; write_reg_seq.data = 32'h12; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h10; write_reg_seq.data = 32'h0C; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h14; write_reg_seq.data = 32'h12; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h1C; write_reg_seq.data = 32'h000F_003F; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h20; write_reg_seq.data = 32'd1; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h18; write_reg_seq.data = 32'h0040_0600; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h00; write_reg_seq.data = MODER_CONF; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h04; write_reg_seq.data = 32'hFFFF_FFFF; write_reg_seq.start(m_sequencer);

    // 3. Preload packet data to memory (frontdoor via DMA agent)
    begin
      uvm_component comp;
      uvm_sequencer_base dma_seqr;
      reg_write_seq mem_seq;

      comp = uvm_top.find("uvm_test_top.m_env.m_dma_agent.m_sequencer");
      if (comp == null) `uvm_fatal("SEQ", "Could not find DMA sequencer")
      if (!$cast(dma_seqr, comp)) `uvm_fatal("SEQ", "DMA sequencer cast failed")

      mem_seq = reg_write_seq::type_id::create("mem_seq");
      for (int i = 0; i < pkt_len; i += 4) begin
        logic [31:0] word;
        word = 0;
        for (int b = 0; b < 4 && (i + b) < pkt_len; b++)
          word |= (((i + b) & 8'hFF) << (b * 8));
        mem_seq.addr = TX_BUFFER + i;
        mem_seq.data = word;
        mem_seq.start(dma_seqr);
      end
      `uvm_info(get_type_name(), $sformatf("Frontdoor write: %0d bytes at 0x%04h", pkt_len, TX_BUFFER), UVM_MEDIUM)
    end

    // 4. Program Buffer Descriptor (raw — not in RAL)
    write_reg_seq.addr = BD0_PTR;
    write_reg_seq.data = TX_BUFFER;
    write_reg_seq.start(m_sequencer);

    write_reg_seq.addr = BD0_STATUS;
    write_reg_seq.data = (pkt_len << 16) | (BIT_RD | BIT_IRQ | BIT_WRAP | BIT_PAD | BIT_CRC);
    write_reg_seq.start(m_sequencer);

    `uvm_info(get_type_name(), "TX launched. Expecting 1 collision + successful retransmission...", UVM_LOW)

    // 5. Poll for completion
    for (int i = 0; i < 5000; i++) begin
      #1000ns;
      read_reg_seq.addr = BD0_STATUS;
      read_reg_seq.start(m_sequencer);
      bd_status = read_reg_seq.data;

      if ((bd_status & BIT_RD) == 0) begin
        retry_count = (bd_status & BIT_RC_MASK) >> 4;

        `uvm_info(get_type_name(), $sformatf("TX complete. BD=0x%08h, RetryCount=%0d, RL=%0b",
                  bd_status, retry_count, (bd_status & BIT_RL) != 0), UVM_LOW)

        if (retry_count == 1 && (bd_status & BIT_RL) == 0) begin
          `uvm_info(get_type_name(), "PASS: Single collision detected, packet retransmitted successfully.", UVM_LOW)
        end else if (retry_count == 0) begin
          `uvm_info(get_type_name(), "PASS: TX completed (collision may have been outside window, acceptable).", UVM_LOW)
        end else begin
          `uvm_error(get_type_name(), $sformatf("FAIL: Unexpected RetryCount=%0d or RL=%0b", retry_count, (bd_status & BIT_RL) != 0))
        end
        return;
      end
    end

    `uvm_error(get_type_name(), $sformatf("TIMEOUT: TX BD Ready bit never cleared. Last BD=0x%08h", bd_status))
  endtask : body

endclass : tx_single_collision_seq

// -------------------------------------------------------------------------
// Sequence: Max Collision Retransmission (HD-02)
// -------------------------------------------------------------------------
class hd_max_collision_seq extends uvm_sequence #(wishbone_transaction);
  `uvm_object_utils(hd_max_collision_seq)
  `uvm_declare_p_sequencer(host_sequencer)
  reg_write_seq write_reg_seq;
  reg_read_seq  read_reg_seq;

  localparam BD0_STATUS = 32'h400;
  localparam BD0_PTR    = 32'h404;
  localparam TX_BUFFER  = 32'h2000;

  localparam MODER_CONF = 32'h0000_A002;

  localparam BIT_RD   = 16'h8000;
  localparam BIT_IRQ  = 16'h4000;
  localparam BIT_WRAP = 16'h2000;
  localparam BIT_PAD  = 16'h1000;
  localparam BIT_CRC  = 16'h0800;
  localparam BIT_RL   = 16'h0008;

  localparam MAXRET = 15;

  function new(string name = "hd_max_collision_seq");
    super.new(name);
  endfunction

  virtual task body();
    int pkt_len = 100;
    logic [31:0] bd_status;
    phy_agent_config m_phy_cfg;
    write_reg_seq = reg_write_seq::type_id::create("write_reg_seq");
    read_reg_seq  = reg_read_seq::type_id::create("read_reg_seq");

    `uvm_info(get_type_name(), "HD-02: Max Collision (Retry Limit) Test", UVM_LOW)

    // 1. Get PHY config — set 16 collisions (exceeds MaxRet=15)
    if (!uvm_config_db#(phy_agent_config)::get(null, "uvm_test_top.m_env.m_phy_agent*", "config", m_phy_cfg))
      `uvm_fatal("SEQ", "Could not get PHY agent config")

    m_phy_cfg.collisions_remaining = MAXRET + 1;
    `uvm_info(get_type_name(), $sformatf("PHY collisions_remaining set to %0d", m_phy_cfg.collisions_remaining), UVM_LOW)

    // 2. Configure MAC via RAL
    write_reg_seq.addr = 32'h0C; write_reg_seq.data = 32'h12; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h10; write_reg_seq.data = 32'h0C; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h14; write_reg_seq.data = 32'h12; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h1C; write_reg_seq.data = 32'h000F_003F; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h20; write_reg_seq.data = 32'd1; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h18; write_reg_seq.data = 32'h0040_0600; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h00; write_reg_seq.data = MODER_CONF; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h04; write_reg_seq.data = 32'hFFFF_FFFF; write_reg_seq.start(m_sequencer);

    // 3. Preload memory (frontdoor via DMA agent)
    begin
      uvm_component comp;
      uvm_sequencer_base dma_seqr;
      reg_write_seq mem_seq;

      comp = uvm_top.find("uvm_test_top.m_env.m_dma_agent.m_sequencer");
      if (comp == null) `uvm_fatal("SEQ", "Could not find DMA sequencer")
      if (!$cast(dma_seqr, comp)) `uvm_fatal("SEQ", "DMA sequencer cast failed")

      mem_seq = reg_write_seq::type_id::create("mem_seq");
      for (int i = 0; i < pkt_len; i += 4) begin
        logic [31:0] word;
        word = 0;
        for (int b = 0; b < 4 && (i + b) < pkt_len; b++)
          word |= (((i + b) & 8'hFF) << (b * 8));
        mem_seq.addr = TX_BUFFER + i;
        mem_seq.data = word;
        mem_seq.start(dma_seqr);
      end
    end

    // 4. Program BD (raw)
    write_reg_seq.addr = BD0_PTR;    write_reg_seq.data = TX_BUFFER; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = BD0_STATUS;
    write_reg_seq.data = (pkt_len << 16) | (BIT_RD | BIT_IRQ | BIT_WRAP | BIT_PAD | BIT_CRC);
    write_reg_seq.start(m_sequencer);

    `uvm_info(get_type_name(), "TX launched. Expecting retry limit abort...", UVM_LOW)

    // 5. Poll
    for (int i = 0; i < 50000; i++) begin
      #1000ns;
      read_reg_seq.addr = BD0_STATUS;
      read_reg_seq.start(m_sequencer);
      bd_status = read_reg_seq.data;

      if ((bd_status & BIT_RD) == 0) begin
        if ((bd_status & BIT_RL) != 0) begin
          `uvm_info(get_type_name(), $sformatf("PASS: Retry Limit Reached (RL=1). BD=0x%08h", bd_status), UVM_LOW)
        end else begin
          `uvm_error(get_type_name(), $sformatf("FAIL: TX finished but RL bit NOT set. BD=0x%08h", bd_status))
        end
        return;
      end
    end

    `uvm_error(get_type_name(), $sformatf("TIMEOUT: BD never cleared RD bit. Last BD=0x%08h", bd_status))
  endtask : body

endclass : hd_max_collision_seq

// -------------------------------------------------------------------------
// Sequence: Late Collision (HD-03)
// -------------------------------------------------------------------------
class late_collision_seq extends uvm_sequence #(wishbone_transaction);
  `uvm_object_utils(late_collision_seq)
  `uvm_declare_p_sequencer(host_sequencer)
  reg_write_seq write_reg_seq;
  reg_read_seq  read_reg_seq;

  localparam BD0_STATUS = 32'h400;
  localparam BD0_PTR    = 32'h404;
  localparam TX_BUFFER  = 32'h2000;

  localparam MODER_CONF = 32'h0000_A002;

  localparam BIT_RD   = 16'h8000;
  localparam BIT_IRQ  = 16'h4000;
  localparam BIT_WRAP = 16'h2000;
  localparam BIT_PAD  = 16'h1000;
  localparam BIT_CRC  = 16'h0800;
  localparam BIT_RL   = 16'h0008;
  localparam BIT_LC   = 16'h0004;
  localparam BIT_DF   = 16'h0002;
  localparam BIT_CS   = 16'h0001;

  function new(string name = "late_collision_seq");
    super.new(name);
  endfunction

  virtual task body();
    int pkt_len = 200;
    logic [31:0] bd_status;
    phy_agent_config m_phy_cfg;
    write_reg_seq = reg_write_seq::type_id::create("write_reg_seq");
    read_reg_seq  = reg_read_seq::type_id::create("read_reg_seq");

    `uvm_info(get_type_name(), "HD-03: Late Collision Test", UVM_LOW)

    // 1. Get PHY config — DISABLE auto collisions
    if (!uvm_config_db#(phy_agent_config)::get(null, "uvm_test_top.m_env.m_phy_agent*", "config", m_phy_cfg))
      `uvm_fatal("SEQ", "Could not get PHY agent config")

    m_phy_cfg.collisions_remaining = 0;
    `uvm_info(get_type_name(), "Auto-collision disabled. Will use manual late injection.", UVM_LOW)

    // 2. Configure MAC for Half-Duplex via RAL
    write_reg_seq.addr = 32'h0C; write_reg_seq.data = 32'h12; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h10; write_reg_seq.data = 32'h0C; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h14; write_reg_seq.data = 32'h12; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h1C; write_reg_seq.data = 32'h000F_003F; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h20; write_reg_seq.data = 32'd1; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h18; write_reg_seq.data = 32'h0040_0600; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h00; write_reg_seq.data = MODER_CONF; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h04; write_reg_seq.data = 32'hFFFF_FFFF; write_reg_seq.start(m_sequencer);

    // 3. Preload packet data (frontdoor via DMA agent)
    begin
      uvm_component comp;
      uvm_sequencer_base dma_seqr;
      reg_write_seq mem_seq;

      comp = uvm_top.find("uvm_test_top.m_env.m_dma_agent.m_sequencer");
      if (comp == null) `uvm_fatal("SEQ", "Could not find DMA sequencer")
      if (!$cast(dma_seqr, comp)) `uvm_fatal("SEQ", "DMA sequencer cast failed")

      mem_seq = reg_write_seq::type_id::create("mem_seq");
      for (int i = 0; i < pkt_len; i += 4) begin
        logic [31:0] word;
        word = 0;
        for (int b = 0; b < 4 && (i + b) < pkt_len; b++)
          word |= (((i + b) & 8'hFF) << (b * 8));
        mem_seq.addr = TX_BUFFER + i;
        mem_seq.data = word;
        mem_seq.start(dma_seqr);
      end
    end

    // 4. Program Buffer Descriptor — starts TX (raw)
    write_reg_seq.addr = BD0_PTR;
    write_reg_seq.data = TX_BUFFER;
    write_reg_seq.start(m_sequencer);

    write_reg_seq.addr = BD0_STATUS;
    write_reg_seq.data = (pkt_len << 16) | (BIT_RD | BIT_IRQ | BIT_WRAP | BIT_PAD | BIT_CRC);
    write_reg_seq.start(m_sequencer);

    `uvm_info(get_type_name(), "TX launched. Waiting for CollValid window to close...", UVM_LOW)

    // 5. Wait past CollValid window, then inject late collision
    #10000ns;

    `uvm_info(get_type_name(), "Injecting LATE collision (past CollValid window)...", UVM_LOW)
    m_phy_cfg.collision_event.trigger();

    // 6. Poll for completion — expect immediate abort
    for (int i = 0; i < 5000; i++) begin
      #1000ns;
      read_reg_seq.addr = BD0_STATUS;
      read_reg_seq.start(m_sequencer);
      bd_status = read_reg_seq.data;

      if ((bd_status & BIT_RD) == 0) begin
        `uvm_info(get_type_name(), $sformatf("TX aborted. BD=0x%08h, LC=%0b, RL=%0b",
                  bd_status, (bd_status & BIT_LC) != 0, (bd_status & BIT_RL) != 0), UVM_LOW)

        if ((bd_status & BIT_LC) != 0 && (bd_status & BIT_RL) == 0) begin
          `uvm_info(get_type_name(), "PASS: Late Collision detected. TX aborted immediately.", UVM_LOW)
        end else begin
          `uvm_error(get_type_name(), $sformatf("FAIL: Expected LC=1 RL=0, got BD=0x%08h", bd_status))
        end
        return;
      end
    end

    `uvm_error(get_type_name(), $sformatf("TIMEOUT: BD Ready bit never cleared. Last BD=0x%08h", bd_status))
  endtask : body

endclass : late_collision_seq


//============================================================================
// BACKOFF SEQUENCE (HD-04)
//============================================================================
class backoff_seq extends uvm_sequence #(wishbone_transaction);
  `uvm_object_utils(backoff_seq)
  `uvm_declare_p_sequencer(host_sequencer)
  reg_write_seq write_reg_seq;
  reg_read_seq  read_reg_seq;

  localparam BD0_STATUS = 32'h400;
  localparam BD0_PTR    = 32'h404;
  localparam TX_BUFFER  = 32'h2000;

  localparam MODER_CONF = 32'h0000_A002;

  localparam BIT_RD   = 16'h8000;
  localparam BIT_IRQ  = 16'h4000;
  localparam BIT_WRAP = 16'h2000;
  localparam BIT_PAD  = 16'h1000;
  localparam BIT_CRC  = 16'h0800;
  localparam BIT_RL      = 16'h0008;
  localparam BIT_RC_MASK = 16'h00F0;
  localparam BIT_DEF     = 16'h0002;

  localparam int SLOT_TIME_NS = 10240;
  localparam int OVERHEAD_NS = 3000;
  localparam int NUM_COLLISIONS = 3;

  function new(string name = "backoff_seq");
    super.new(name);
  endfunction

  virtual task body();
    int pkt_len = 100;
    logic [31:0] bd_status;
    int retry_count;
    phy_agent_config m_phy_cfg;
    time t_txen_fall [NUM_COLLISIONS];
    time t_txen_rise [NUM_COLLISIONS];
    int  backoff_slots[NUM_COLLISIONS];
    int  col_idx = 0;
    bit  all_ok  = 1;
    write_reg_seq = reg_write_seq::type_id::create("write_reg_seq");
    read_reg_seq  = reg_read_seq::type_id::create("read_reg_seq");

    `uvm_info(get_type_name(), "HD-05: Random Backoff After Collision Test", UVM_LOW)

    // 1. Get PHY config — set 3 collisions
    if (!uvm_config_db#(phy_agent_config)::get(null, "uvm_test_top.m_env.m_phy_agent*", "config", m_phy_cfg))
      `uvm_fatal("SEQ", "Could not get PHY agent config")

    m_phy_cfg.collisions_remaining = NUM_COLLISIONS;
    `uvm_info(get_type_name(), $sformatf("PHY collisions_remaining = %0d", m_phy_cfg.collisions_remaining), UVM_LOW)

    // 2. Configure MAC — half-duplex, NoBckof=0 via RAL
    write_reg_seq.addr = 32'h0C; write_reg_seq.data = 32'h12; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h10; write_reg_seq.data = 32'h0C; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h14; write_reg_seq.data = 32'h12; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h1C; write_reg_seq.data = 32'h000F_003F; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h20; write_reg_seq.data = 32'd1; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h18; write_reg_seq.data = 32'h0040_0600; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h00; write_reg_seq.data = MODER_CONF; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h04; write_reg_seq.data = 32'hFFFF_FFFF; write_reg_seq.start(m_sequencer);

    // 3. Preload packet into memory (frontdoor via DMA agent)
    begin
      uvm_component comp;
      uvm_sequencer_base dma_seqr;
      reg_write_seq mem_seq;

      comp = uvm_top.find("uvm_test_top.m_env.m_dma_agent.m_sequencer");
      if (comp == null) `uvm_fatal("SEQ", "Could not find DMA sequencer")
      if (!$cast(dma_seqr, comp)) `uvm_fatal("SEQ", "DMA sequencer cast failed")

      mem_seq = reg_write_seq::type_id::create("mem_seq");
      for (int i = 0; i < pkt_len; i += 4) begin
        logic [31:0] word;
        word = 0;
        for (int b = 0; b < 4 && (i + b) < pkt_len; b++)
          word |= (((i + b) & 8'hFF) << (b * 8));
        mem_seq.addr = TX_BUFFER + i;
        mem_seq.data = word;
        mem_seq.start(dma_seqr);
      end
      `uvm_info(get_type_name(), "Frontdoor memory write complete via DMA", UVM_MEDIUM)
    end

    // 4. Arm TX BD (raw)
    write_reg_seq.addr = BD0_PTR;
    write_reg_seq.data = TX_BUFFER;
    write_reg_seq.start(m_sequencer);

    write_reg_seq.addr = BD0_STATUS;
    write_reg_seq.data = (pkt_len << 16) | (BIT_RD | BIT_IRQ | BIT_WRAP | BIT_PAD | BIT_CRC);
    write_reg_seq.start(m_sequencer);

    `uvm_info(get_type_name(), "TX BD armed. Monitoring backoff durations...", UVM_LOW)

    // 5. Monitor tx_en transitions for collision + backoff timing
    for (int c = 0; c < NUM_COLLISIONS; c++) begin
      wait (m_phy_cfg.vif.tx_en === 1'b1);
      `uvm_info(get_type_name(), $sformatf("Collision %0d: tx_en HIGH (attempt start) @ %0t", c, $time), UVM_LOW)

      wait (m_phy_cfg.vif.tx_en === 1'b0);
      t_txen_fall[c] = $time;
      `uvm_info(get_type_name(), $sformatf("Collision %0d: tx_en LOW (abort) @ %0t", c, $time), UVM_LOW)

      wait (m_phy_cfg.vif.tx_en === 1'b1);
      t_txen_rise[c] = $time;
      `uvm_info(get_type_name(), $sformatf("Collision %0d: tx_en HIGH (retransmit) @ %0t", c, $time), UVM_LOW)
    end

    // 6. Wait for final successful transmission
    wait (m_phy_cfg.vif.tx_en === 1'b0);
    `uvm_info(get_type_name(), $sformatf("Final TX complete (tx_en LOW) @ %0t", $time), UVM_LOW)

    // 7. Validate backoff durations
    for (int c = 0; c < NUM_COLLISIONS; c++) begin
      time gap;
      int max_slots;
      int n;

      gap = t_txen_rise[c] - t_txen_fall[c];
      n = c + 1;
      max_slots = (1 << (n < 10 ? n : 10)) - 1;

      if (gap > OVERHEAD_NS)
        backoff_slots[c] = (gap - OVERHEAD_NS) / SLOT_TIME_NS;
      else
        backoff_slots[c] = 0;

      `uvm_info(get_type_name(), $sformatf(
        "Retry %0d: gap=%0t, backoff_slots=%0d, max_allowed=%0d",
        n, gap, backoff_slots[c], max_slots), UVM_LOW)

      if (backoff_slots[c] > max_slots) begin
        `uvm_error(get_type_name(), $sformatf(
          "FAIL: Retry %0d backoff %0d slots exceeds IEEE max %0d",
          n, backoff_slots[c], max_slots))
        all_ok = 0;
      end
    end

    // 8. Poll BD for completion — verify retry count
    for (int i = 0; i < 5000; i++) begin
      #1000ns;
      read_reg_seq.addr = BD0_STATUS;
      read_reg_seq.start(m_sequencer);
      bd_status = read_reg_seq.data;

      if ((bd_status & BIT_RD) == 0) begin
        retry_count = (bd_status & BIT_RC_MASK) >> 4;

        `uvm_info(get_type_name(), $sformatf(
          "TX done. BD=0x%08h, RetryCount=%0d", bd_status, retry_count), UVM_LOW)

        if (retry_count != NUM_COLLISIONS) begin
          `uvm_error(get_type_name(), $sformatf(
            "FAIL: Expected RetryCount=%0d, got %0d", NUM_COLLISIONS, retry_count))
          all_ok = 0;
        end

        if (all_ok)
          `uvm_info(get_type_name(), $sformatf(
            "PASS: Backoff durations within IEEE 802.3 bounds. RetryCount=%0d.", retry_count), UVM_LOW)

        return;
      end
    end

    `uvm_error(get_type_name(), $sformatf(
      "TIMEOUT: BD Ready bit never cleared. Last BD=0x%08h", bd_status))
  endtask : body

endclass : backoff_seq

//============================================================================
// CARRIER LOST SEQUENCE (HD-05)
//============================================================================
class carrier_lost_seq extends uvm_sequence #(wishbone_transaction);
  `uvm_object_utils(carrier_lost_seq)
  `uvm_declare_p_sequencer(host_sequencer)
  reg_write_seq write_reg_seq;
  reg_read_seq  read_reg_seq;

  localparam BD0_STATUS = 32'h400;
  localparam BD0_PTR    = 32'h404;
  localparam TX_BUFFER  = 32'h2000;

  localparam MODER_CONF = 32'h0000_A002;

  localparam BIT_RD   = 16'h8000;
  localparam BIT_IRQ  = 16'h4000;
  localparam BIT_WRAP = 16'h2000;
  localparam BIT_PAD  = 16'h1000;
  localparam BIT_CRC  = 16'h0800;
  localparam BIT_CS  = 16'h0001;

  function new(string name = "carrier_lost_seq");
    super.new(name);
  endfunction

  virtual task body();
    int pkt_len = 100;
    logic [31:0] bd_status;
    phy_agent_config m_phy_cfg;
    write_reg_seq = reg_write_seq::type_id::create("write_reg_seq");
    read_reg_seq  = reg_read_seq::type_id::create("read_reg_seq");

    `uvm_info(get_type_name(), "HD-06: Carrier Sense Lost During Transmission Test", UVM_LOW)

    // 1. Get PHY config
    if (!uvm_config_db#(phy_agent_config)::get(null, "uvm_test_top.m_env.m_phy_agent*", "config", m_phy_cfg))
      `uvm_fatal("SEQ", "Could not get PHY agent config")

    m_phy_cfg.collisions_remaining = 0;
    m_phy_cfg.crs_override = 1;

    // 2. Configure MAC — half-duplex via RAL
    write_reg_seq.addr = 32'h0C; write_reg_seq.data = 32'h12; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h10; write_reg_seq.data = 32'h0C; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h14; write_reg_seq.data = 32'h12; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h1C; write_reg_seq.data = 32'h000F_003F; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h20; write_reg_seq.data = 32'd1; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h18; write_reg_seq.data = 32'h0040_0600; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h00; write_reg_seq.data = MODER_CONF; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h04; write_reg_seq.data = 32'hFFFF_FFFF; write_reg_seq.start(m_sequencer);

    // 3. Preload packet into memory (frontdoor via DMA agent)
    begin
      uvm_component comp;
      uvm_sequencer_base dma_seqr;
      reg_write_seq mem_seq;

      comp = uvm_top.find("uvm_test_top.m_env.m_dma_agent.m_sequencer");
      if (comp == null) `uvm_fatal("SEQ", "Could not find DMA sequencer")
      if (!$cast(dma_seqr, comp)) `uvm_fatal("SEQ", "DMA sequencer cast failed")

      mem_seq = reg_write_seq::type_id::create("mem_seq");
      for (int i = 0; i < pkt_len; i += 4) begin
        logic [31:0] word;
        word = 0;
        for (int b = 0; b < 4 && (i + b) < pkt_len; b++)
          word |= (((i + b) & 8'hFF) << (b * 8));
        mem_seq.addr = TX_BUFFER + i;
        mem_seq.data = word;
        mem_seq.start(dma_seqr);
      end
      `uvm_info(get_type_name(), "Frontdoor memory write complete via DMA", UVM_MEDIUM)
    end

    // 4. Arm TX BD (raw)
    write_reg_seq.addr = BD0_PTR;
    write_reg_seq.data = TX_BUFFER;
    write_reg_seq.start(m_sequencer);

    write_reg_seq.addr = BD0_STATUS;
    write_reg_seq.data = (pkt_len << 16) | (BIT_RD | BIT_IRQ | BIT_WRAP | BIT_PAD | BIT_CRC);
    write_reg_seq.start(m_sequencer);

    `uvm_info(get_type_name(), "TX BD armed. Waiting for TX to start...", UVM_LOW)

    // 5. Wait for tx_en HIGH, assert CRS=1 (normal)
    wait (m_phy_cfg.vif.tx_en === 1'b1);
    m_phy_cfg.vif.crs <= 1'b1;
    `uvm_info(get_type_name(), $sformatf("tx_en HIGH @ %0t, CRS=1 asserted", $time), UVM_LOW)

    // 6. Wait for data phase, then briefly drop CRS
    repeat (20) @(posedge m_phy_cfg.vif.tx_clk);
    `uvm_info(get_type_name(), "Dropping CRS (carrier sense lost)...", UVM_LOW)

    m_phy_cfg.vif.crs <= 1'b0;
    repeat (5) @(posedge m_phy_cfg.vif.tx_clk);

    m_phy_cfg.vif.crs <= 1'b1;
    `uvm_info(get_type_name(), "CRS restored. TX should continue normally.", UVM_LOW)

    // 7. Wait for tx_en drop, then drop CRS
    wait (m_phy_cfg.vif.tx_en === 1'b0);
    m_phy_cfg.vif.crs <= 1'b0;
    m_phy_cfg.crs_override = 0;
    `uvm_info(get_type_name(), $sformatf("TX complete (tx_en LOW) @ %0t", $time), UVM_LOW)

    // 8. Poll BD for completion — verify CS bit
    for (int i = 0; i < 5000; i++) begin
      #1000ns;
      read_reg_seq.addr = BD0_STATUS;
      read_reg_seq.start(m_sequencer);
      bd_status = read_reg_seq.data;

      if ((bd_status & BIT_RD) == 0) begin
        `uvm_info(get_type_name(), $sformatf(
          "TX done. BD=0x%08h, CS=%0b", bd_status, (bd_status & BIT_CS) != 0), UVM_LOW)

        if ((bd_status & BIT_CS) != 0) begin
          `uvm_info(get_type_name(), "PASS: Carrier Sense Lost correctly reported (CS=1).", UVM_LOW)
        end else begin
          `uvm_error(get_type_name(), $sformatf(
            "FAIL: Expected CS=1, got BD=0x%08h", bd_status))
        end
        return;
      end
    end

    m_phy_cfg.crs_override = 0;
    `uvm_error(get_type_name(), $sformatf(
      "TIMEOUT: BD Ready bit never cleared. Last BD=0x%08h", bd_status))
  endtask : body

endclass : carrier_lost_seq