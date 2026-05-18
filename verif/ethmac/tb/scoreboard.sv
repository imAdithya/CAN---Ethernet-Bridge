`include "uvm_macros.svh"
import uvm_pkg::*;
`include "ethmac_defines.v"

class scoreboard extends uvm_scoreboard;
  `uvm_component_utils(scoreboard)

  //================== TLM PORTS ==================
  uvm_analysis_export #(wishbone_transaction) host_export;
  uvm_analysis_export #(wishbone_transaction) dma_export;
  uvm_analysis_export #(ethernet_frame_transaction) phy_export;

  uvm_tlm_analysis_fifo #(wishbone_transaction) host_fifo;
  uvm_tlm_analysis_fifo #(wishbone_transaction) dma_fifo;
  uvm_tlm_analysis_fifo #(ethernet_frame_transaction) phy_fifo;
  
  // Configuration
  bit disable_rx_check = 0;  // Disable RX verification for specific tests

  // MIIM MDIO Bus Monitor
  virtual mii_if   vif_mii;              // MII interface for MDIO monitoring
  logic [15:0]     miim_phy_regs [32];   // Internal PHY register model
  bit              miim_reg_written [32]; // Track registers written via MIIM
  bit              miim_check_enabled;   // Enable MIIM bus checking

  //================== REGISTER MODEL =============
  local logic [31:0] reg_model [logic [31:0]];
  local logic [31:0] reg_masks [logic [31:0]];

  //================== RX DMA BUFFER ==============
  byte unsigned rx_dma_buffer[$];

  //------------------------------------------------
  // BYTE-ADDRESS LOCALPARAMS
  //------------------------------------------------
  localparam ADDR_MODER       = (`ETH_MODER_ADR        << 2);
  localparam ADDR_INT_SOURCE  = (`ETH_INT_SOURCE_ADR   << 2);
  localparam ADDR_INT_MASK    = (`ETH_INT_MASK_ADR     << 2);
  localparam ADDR_IPGT        = (`ETH_IPGT_ADR         << 2);
  localparam ADDR_IPGR1       = (`ETH_IPGR1_ADR        << 2);
  localparam ADDR_IPGR2       = (`ETH_IPGR2_ADR        << 2);
  localparam ADDR_PACKETLEN   = (`ETH_PACKETLEN_ADR    << 2);
  localparam ADDR_COLLCONF    = (`ETH_COLLCONF_ADR     << 2);
  localparam ADDR_TX_BD_NUM   = (`ETH_TX_BD_NUM_ADR    << 2);
  localparam ADDR_CTRLMODER   = (`ETH_CTRLMODER_ADR    << 2);
  localparam ADDR_MIIMODER    = (`ETH_MIIMODER_ADR     << 2);
  localparam ADDR_MIICOMMAND  = (`ETH_MIICOMMAND_ADR   << 2);
  localparam ADDR_MIIADDRESS  = (`ETH_MIIADDRESS_ADR   << 2);
  localparam ADDR_MIITX_DATA  = (`ETH_MIITX_DATA_ADR   << 2);
  localparam ADDR_MIIRX_DATA  = (`ETH_MIIRX_DATA_ADR   << 2);
  localparam ADDR_MIISTATUS   = (`ETH_MIISTATUS_ADR    << 2);
  localparam ADDR_MAC_ADDR0   = (`ETH_MAC_ADDR0_ADR    << 2);
  localparam ADDR_MAC_ADDR1   = (`ETH_MAC_ADDR1_ADR    << 2);
  localparam ADDR_HASH0       = (`ETH_HASH0_ADR        << 2);
  localparam ADDR_HASH1       = (`ETH_HASH1_ADR        << 2);
  localparam ADDR_TX_CTRL     = (`ETH_TX_CTRL_ADR      << 2);

  //------------------------------------------------
  // CONSTRUCTOR
  //------------------------------------------------
  function new(string name="scoreboard", uvm_component parent=null);
    super.new(name, parent);

    //---------------- MASKS ----------------
    reg_masks[ADDR_MODER]       = 32'h0001_FFFF;
    reg_masks[ADDR_INT_SOURCE]  = 32'h0;
    reg_masks[ADDR_INT_MASK]    = 32'h0000_007F;
    reg_masks[ADDR_IPGT]        = 32'h0000_007F;
    reg_masks[ADDR_IPGR1]       = 32'h0000_007F;
    reg_masks[ADDR_IPGR2]       = 32'h0000_007F;
    reg_masks[ADDR_PACKETLEN]   = 32'hFFFF_FFFF;
    reg_masks[ADDR_COLLCONF]    = 32'h000F_003F;
    reg_masks[ADDR_TX_BD_NUM]   = 32'h0000_00FF;
    reg_masks[ADDR_CTRLMODER]   = 32'h0000_0007;
    reg_masks[ADDR_MIIMODER]    = 32'h0000_01FF;
    reg_masks[ADDR_MIICOMMAND]  = 32'h0000_0007;
    reg_masks[ADDR_MIIADDRESS]  = 32'h0000_1F1F;
    reg_masks[ADDR_MIITX_DATA]  = 32'h0000_FFFF;
    reg_masks[ADDR_MIIRX_DATA]  = 32'h0;
    reg_masks[ADDR_MIISTATUS]   = 32'h0;
    reg_masks[ADDR_MAC_ADDR0]   = 32'hFFFF_FFFF;
    reg_masks[ADDR_MAC_ADDR1]   = 32'h0000_FFFF;
    reg_masks[ADDR_HASH0]       = 32'hFFFF_FFFF;
    reg_masks[ADDR_HASH1]       = 32'hFFFF_FFFF;
    reg_masks[ADDR_TX_CTRL]     = 32'h0001_FFFF;

    //---------------- RESET VALUES ----------------
    // (Kept same as provided)
    reg_model[ADDR_MODER]       = {15'h0, `ETH_MODER_DEF_2, `ETH_MODER_DEF_1, `ETH_MODER_DEF_0};
    reg_model[ADDR_INT_SOURCE]  = 32'h0;
    reg_model[ADDR_INT_MASK]    = {25'h0, `ETH_INT_MASK_DEF_0};
    reg_model[ADDR_IPGT]        = {25'h0, `ETH_IPGT_DEF_0};
    reg_model[ADDR_IPGR1]       = {25'h0, `ETH_IPGR1_DEF_0};
    reg_model[ADDR_IPGR2]       = {25'h0, `ETH_IPGR2_DEF_0};
    reg_model[ADDR_PACKETLEN]   = {`ETH_PACKETLEN_DEF_3, `ETH_PACKETLEN_DEF_2, `ETH_PACKETLEN_DEF_1, `ETH_PACKETLEN_DEF_0};
    reg_model[ADDR_COLLCONF]    = {12'h0, `ETH_COLLCONF_DEF_2, 10'h0, `ETH_COLLCONF_DEF_0};
    reg_model[ADDR_TX_BD_NUM]   = {24'h0, `ETH_TX_BD_NUM_DEF_0};
    reg_model[ADDR_CTRLMODER]   = {29'h0, `ETH_CTRLMODER_DEF_0};
    reg_model[ADDR_MIIMODER]    = {23'h0, `ETH_MIIMODER_DEF_1, 8'h0, `ETH_MIIMODER_DEF_0};
    reg_model[ADDR_MIICOMMAND]  = 32'h0;
    reg_model[ADDR_MIIADDRESS]  = {22'h0, `ETH_MIIADDRESS_DEF_1, 3'h0, `ETH_MIIADDRESS_DEF_0};
    reg_model[ADDR_MIITX_DATA]  = {16'h0, `ETH_MIITX_DATA_DEF_1, 8'h0, `ETH_MIITX_DATA_DEF_0};
    reg_model[ADDR_MIIRX_DATA]  = 32'h0;
    reg_model[ADDR_MIISTATUS]   = 32'h0;
    reg_model[ADDR_MAC_ADDR0]   = 32'h0;
    reg_model[ADDR_MAC_ADDR1]   = 32'h0;
    reg_model[ADDR_HASH0]       = 32'h0;
    reg_model[ADDR_HASH1]       = 32'h0;
    reg_model[ADDR_TX_CTRL]     = 32'h0;
  endfunction

  //------------------------------------------------
  // BUILD / CONNECT
  //------------------------------------------------
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    host_export = new("host_export", this);
    dma_export  = new("dma_export",  this);
    phy_export  = new("phy_export",  this);

    host_fifo = new("host_fifo", this);
    dma_fifo  = new("dma_fifo",  this);
    phy_fifo  = new("phy_fifo",  this);
    
    // Check configuration to disable RX checking
    if (!uvm_config_db#(bit)::get(this, "", "disable_rx_check", disable_rx_check)) begin
      disable_rx_check = 0;
    end
    if (disable_rx_check) begin
      `uvm_info("SCOREBOARD", "RX path checking DISABLED for this test", UVM_LOW)
    end

    // MIIM bus monitor config
    if (!uvm_config_db#(bit)::get(this, "", "miim_check_enabled", miim_check_enabled))
      miim_check_enabled = 0;
    if (!uvm_config_db#(virtual mii_if)::get(this, "", "vif_mii", vif_mii))
      vif_mii = null;
    // Initialize PHY register model
    foreach (miim_phy_regs[i]) begin
      miim_phy_regs[i] = 16'h0;
      miim_reg_written[i] = 0;
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    host_export.connect(host_fifo.analysis_export);
    dma_export.connect(dma_fifo.analysis_export);
    phy_export.connect(phy_fifo.analysis_export);
  endfunction

  //------------------------------------------------
  // RUN
  //------------------------------------------------
  task run_phase(uvm_phase phase);
    fork
      check_registers();
      //check_tx_path();
      collect_rx_dma();
      check_rx_path();
      if (miim_check_enabled && vif_mii != null)
        check_miim_bus();
    join_none
  endtask

  //============== REGISTER CHECK ===================
  task check_registers();
    wishbone_transaction txn;
    logic [31:0] expected, mask, addr; // Added 'addr'

    forever begin
      host_fifo.get(txn);

      // [FIX] Mask the Base Address (0xD000_0000) to get the Offset (Lower 16 bits)
      // Your defines use offsets like 0x00, 0x40, etc.
      addr = txn.address & 32'h0000_FFFF; 

      if (!reg_masks.exists(addr)) // Use 'addr' instead of 'txn.address'
        continue;

      mask = reg_masks[addr];

      // ------------ READ ------------
      if (txn.is_read) begin
        // Skip HW-controlled registers that change independently
        if (addr == 32'h4 || addr == ADDR_MIISTATUS || addr == ADDR_MIIRX_DATA || addr == ADDR_MIICOMMAND) begin
          `uvm_info("REG_RD_SKIP", $sformatf("Skipping HW-controlled reg check (addr=0x%0h)", addr), UVM_HIGH)
        end
        else if (reg_model.exists(addr)) begin
          expected = reg_model[addr];

          if (txn.read_data !== expected)
            `uvm_error("REG_RD_FAIL",
              $sformatf("ADDR 0x%0h read 0x%0h exp 0x%0h",
                  txn.address, txn.read_data, expected))
          else
            `uvm_info("REG_RD_PASS",
              $sformatf("ADDR 0x%0h read 0x%0h MATCH",
                  txn.address, txn.read_data),
              UVM_LOW)
        end
      end

      // ------------ WRITE ------------
      else begin
        if (mask != 0) begin
          reg_model[addr] = txn.write_data & mask;
          // Optional: Print Write Success for debugging
          `uvm_info("REG_WR", $sformatf("ADDR 0x%0h updated to 0x%0h", addr, txn.write_data & mask), UVM_HIGH)
        end
      end
    end
  endtask

  //============== TX DATA CHECK ====================
  task check_tx_path();
    wishbone_transaction dma_txn;
    ethernet_frame_transaction phy_frame;
    logic [7:0] dma_payload[$];

    forever begin
      dma_payload.delete();
      dma_fifo.get(dma_txn);
      // Wait for TX Buffer read (0x0000 - 0x1FFF region)
      if (!dma_txn.is_read || dma_txn.address >= 32'h2000)
        continue;

      // Collect contiguous reads
      do begin
        for (int i=0;i<4;i++)
          if (dma_txn.sel[i])
            dma_payload.push_back(dma_txn.read_data[i*8 +: 8]);

        dma_fifo.peek(dma_txn);
        if (!dma_txn.is_read || dma_txn.address >= 32'h2000)
          break;

        dma_fifo.get(dma_txn);
      end while (1);

      phy_fifo.get(phy_frame);

      // Check Payload size matching
      if (dma_payload.size() != phy_frame.payload.size())
        `uvm_error("TX_SIZE_MISMATCH",
          $sformatf("DMA=%0d PHY=%0d",
            dma_payload.size(), phy_frame.payload.size()))
      else begin
        foreach (dma_payload[i])
          if (dma_payload[i] != phy_frame.payload[i]) begin
            `uvm_error("TX_DATA_MISMATCH",
              $sformatf("Byte %0d DMA=%0h PHY=%0h",
                  i, dma_payload[i], phy_frame.payload[i]))
            break;
          end
        `uvm_info("TX_PASS","TX payload matches DMA data",UVM_LOW)
      end
    end
  endtask

  // =========================================================
  // COLLECT RX DMA (Always runs in background)
  // =========================================================
  task collect_rx_dma();
    wishbone_transaction dma_txn;
    forever begin
      dma_fifo.get(dma_txn);
      // Filter for Writes to RX Buffer (0x2000+)
      if (!dma_txn.is_read && dma_txn.address >= 32'h2000) begin
        // The MAC stores bytes in little-endian order within 32-bit words
        // Extract bytes from  highest to lowest index to get correct Ethernet frame order
        for (int i = 3; i >= 0; i--) begin
          if (dma_txn.sel[i]) 
            rx_dma_buffer.push_back(dma_txn.write_data[i*8 +: 8]);
        end
      end
    end
  endtask

  //------------------------------------------------
  // ADDRESS FILTERING HELPERS
  //------------------------------------------------
  
  // Extract configured MAC address from registers
  // Ethernet MAC Address: mac[0]:mac[1]:mac[2]:mac[3]:mac[4]:mac[5] = 02:03:04:05:06:07
  // MAC_ADDR1[15:0] = {mac[0], mac[1]} = 0x0203
  // MAC_ADDR0[31:0] = {mac[2], mac[3], mac[4], mac[5]} = 0x04050607
  function void get_mac_addr(output byte unsigned mac_addr[6]);
    mac_addr[0] = reg_model[ADDR_MAC_ADDR1][15:8];
    mac_addr[1] = reg_model[ADDR_MAC_ADDR1][7:0];
    mac_addr[2] = reg_model[ADDR_MAC_ADDR0][31:24];
    mac_addr[3] = reg_model[ADDR_MAC_ADDR0][23:16];
    mac_addr[4] = reg_model[ADDR_MAC_ADDR0][15:8];
    mac_addr[5] = reg_model[ADDR_MAC_ADDR0][7:0];
  endfunction

  // Check if destination address matches our configured MAC
  function bit matches_our_mac(byte unsigned dest_addr[6]);
    byte unsigned our_mac[6];
    get_mac_addr(our_mac);
    
    foreach (dest_addr[i]) begin
      if (dest_addr[i] != our_mac[i]) 
        return 0;
    end
    return 1;
  endfunction

  // Determine if packet should be filtered (rejected) by MAC hardware
  // Returns: 1 = filtered/rejected, 0 = accepted
  function bit should_be_filtered(byte unsigned dest_addr[6]);
    bit pro, bro;
    bit is_broadcast, is_multicast;
    
    // Get MODER register bits
    if (reg_model.exists(ADDR_MODER)) begin
      pro = reg_model[ADDR_MODER][5];  // Promiscuous mode
      bro = reg_model[ADDR_MODER][3];  // Broadcast reject
    end else begin
      pro = 0;
      bro = 0;
    end
    
    // Check address type
    is_broadcast = (dest_addr[0] == 8'hFF && dest_addr[1] == 8'hFF && 
                    dest_addr[2] == 8'hFF && dest_addr[3] == 8'hFF &&
                    dest_addr[4] == 8'hFF && dest_addr[5] == 8'hFF);
    is_multicast = (dest_addr[0] & 8'h01) && !is_broadcast;  // LSB=1 but not broadcast
    
    // Filtering decision logic
    if (pro) return 0;  // Promiscuous mode: accept all packets
    if (matches_our_mac(dest_addr)) return 0;  // Our MAC address: always accept
    if (is_broadcast && !bro) return 0;  // Broadcast: accept if BRO=0 (don't reject)
    
    // Everything else (multicast, unicast to other MACs): filtered/rejected
    return 1;
  endfunction

  //------------------------------------------------
  // RX PATH VERIFICATION
  //------------------------------------------------
  task check_rx_path();
    ethernet_frame_transaction exp_frame;
    byte unsigned exp_data[$];
    byte unsigned act_data[$];
    bit mismatch;
    int wait_cycles;

    forever begin
      exp_data.delete();
      act_data.delete();
      mismatch = 0;
      wait_cycles = 0;

      // 1. Wait for PHY Frame (Reference)
      phy_fifo.get(exp_frame);

      `uvm_info("SCB_RX", $sformatf("Received PHY frame. Payload=%0d bytes", exp_frame.payload.size()), UVM_LOW)
      
      // Skip verification if disabled
      if (disable_rx_check) begin
        `uvm_info("SCB_RX", "Skipping RX verification (disabled)", UVM_HIGH)
        continue;
      end

      // Check if packet should be filtered by MAC hardware
      if (should_be_filtered(exp_frame.dest_addr)) begin
        `uvm_info("SCB_RX", $sformatf("Packet to %02x:%02x:%02x:%02x:%02x:%02x filtered by MAC (expected behavior)", 
                  exp_frame.dest_addr[0], exp_frame.dest_addr[1], exp_frame.dest_addr[2],
                  exp_frame.dest_addr[3], exp_frame.dest_addr[4], exp_frame.dest_addr[5]), UVM_MEDIUM)
        continue;  // Skip DMA verification for filtered packets
      end else begin
        byte unsigned our_mac[6];
        get_mac_addr(our_mac);
        `uvm_info("SCB_RX", $sformatf("Packet to %02x:%02x:%02x:%02x:%02x:%02x accepted (our MAC: %02x:%02x:%02x:%02x:%02x:%02x)", 
                  exp_frame.dest_addr[0], exp_frame.dest_addr[1], exp_frame.dest_addr[2],
                  exp_frame.dest_addr[3], exp_frame.dest_addr[4], exp_frame.dest_addr[5],
                  our_mac[0], our_mac[1], our_mac[2], our_mac[3], our_mac[4], our_mac[5]), UVM_HIGH)
      end

      // 2. Construct Expected Byte Stream
      foreach (exp_frame.dest_addr[i]) exp_data.push_back(exp_frame.dest_addr[i]);
      foreach (exp_frame.src_addr[i])  exp_data.push_back(exp_frame.src_addr[i]);
      exp_data.push_back(exp_frame.type_len[15:8]);
      exp_data.push_back(exp_frame.type_len[7:0]);
      foreach (exp_frame.payload[i])   exp_data.push_back(exp_frame.payload[i]);
      // CRC
      exp_data.push_back(exp_frame.fcs[7:0]);
      exp_data.push_back(exp_frame.fcs[15:8]);
      exp_data.push_back(exp_frame.fcs[23:16]);
      exp_data.push_back(exp_frame.fcs[31:24]);

      // 3. Wait for DMA Buffer to fill
      while (rx_dma_buffer.size() < exp_data.size()) begin
        #100ns;
        wait_cycles++;
        if (wait_cycles > 50) begin
           `uvm_error("SCB_RX", $sformatf("DMA timeout! Expected %0d bytes, got %0d", 
                                           exp_data.size(), rx_dma_buffer.size()))
           break;
        end
      end

      // DEBUG: Show first 20 bytes of expected and actual data
      if (rx_dma_buffer.size() >= 20) begin
        string exp_str, act_str;
        for (int i = 0; i < 20; i++) begin
          exp_str = {exp_str, $sformatf("%02x ", exp_data[i])};
          if (i < rx_dma_buffer.size())
            act_str = {act_str, $sformatf("%02x ", rx_dma_buffer[i])};
        end
        `uvm_info("SCB_RX_DEBUG", $sformatf("First 20 bytes:\nExp: %s\nAct: %s", exp_str, act_str), UVM_LOW)
      end

      // 4. Compare & Consume
      if (rx_dma_buffer.size() >= exp_data.size()) begin
        for (int i = 0; i < exp_data.size(); i++) begin
           byte act = rx_dma_buffer.pop_front();
           if (act !== exp_data[i]) begin
             mismatch = 1;
             `uvm_error("SCB_RX", $sformatf("Mismatch byte %0d: Exp %02x Act %02x", i, exp_data[i], act))
           end
        end

        // CRITICAL FIX: Clear any remaining bytes in buffer after consuming this packet
        // This prevents leftover bytes from one packet bleeding into the next packet's verification
        // (occurs with multi-BD configuration where packets land in separate buffers)
        if (rx_dma_buffer.size() > 0) begin
          `uvm_info("SCB_RX_DEBUG", $sformatf("Clearing %0d residual bytes from buffer", rx_dma_buffer.size()), UVM_HIGH)
          rx_dma_buffer.delete();
        end

        if (!mismatch)
          `uvm_info("SCB_RX_PASS", "RX Packet Verified Successfully!", UVM_LOW)
      end
    end
  endtask

  //============== MIIM MDIO BUS MONITOR ===========
  // Passively decodes MDC/MDIO serial frames.
  // Write frames update miim_phy_regs; read frames
  // compare PHY response data against the model.
  //=================================================
  task check_miim_bus();
    logic [1:0]  op;
    logic [4:0]  phy_addr, reg_addr;
    logic [15:0] wr_data, rd_data;

    `uvm_info("MIIM_BUS_MON", "MDIO bus monitor started", UVM_LOW)

    forever begin
      // ---- 1. Wait for first start bit (MDIO goes 0 while MDC high) ----
      wait (vif_mii.mdc === 1 && vif_mii.mdio_i === 0);
      @(posedge vif_mii.mdc);

      // ---- 2. Check second start bit (must be 1) ----
      if (vif_mii.mdio_i !== 1) continue;

      // ---- 3. Read op-code (2 bits) ----
      @(posedge vif_mii.mdc);
      op[1] = vif_mii.mdio_i;
      @(posedge vif_mii.mdc);
      op[0] = vif_mii.mdio_i;

      // ---- 4. Read PHY address (5 bits, MSB first) ----
      for (int i = 4; i >= 0; i--) begin
        @(posedge vif_mii.mdc);
        phy_addr[i] = vif_mii.mdio_i;
      end

      // ---- 5. Read register address (5 bits, MSB first) ----
      for (int i = 4; i >= 0; i--) begin
        @(posedge vif_mii.mdc);
        reg_addr[i] = vif_mii.mdio_i;
      end

      // ---- 6. Turnaround (2 bits) ----
      @(posedge vif_mii.mdc); // TA bit 1
      @(posedge vif_mii.mdc); // TA bit 2

      // ---- 7. Read 16 data bits (MSB first) ----
      if (op == 2'b01) begin
        // WRITE frame: MAC drives data
        for (int i = 15; i >= 0; i--) begin
          @(posedge vif_mii.mdc);
          wr_data[i] = vif_mii.mdio_i;
        end
        if (phy_addr == 5'd1) begin // Only track our PHY
          miim_phy_regs[reg_addr] = wr_data;
          miim_reg_written[reg_addr] = 1;
          `uvm_info("MIIM_BUS_MON", $sformatf(
            "WRITE PHY[%0d] REG[%0d] <- 0x%04h",
            phy_addr, reg_addr, wr_data), UVM_MEDIUM)
        end else
          `uvm_info("MIIM_BUS_MON", $sformatf(
            "WRITE PHY[%0d] REG[%0d] <- 0x%04h (non-tracked PHY)",
            phy_addr, reg_addr, wr_data), UVM_MEDIUM)

      end else if (op == 2'b10) begin
        // READ frame: PHY drives data
        for (int i = 15; i >= 0; i--) begin
          @(posedge vif_mii.mdc);
          rd_data[i] = vif_mii.mdio_i;
        end

        if (phy_addr != 5'd1) begin
          // Non-tracked PHY — log but don't compare
          `uvm_info("MIIM_BUS_MON", $sformatf(
            "READ PHY[%0d] REG[%0d] = 0x%04h (non-tracked PHY, skipping check)",
            phy_addr, reg_addr, rd_data), UVM_LOW)
        end else if (!miim_reg_written[reg_addr]) begin
          `uvm_info("MIIM_BUS_MON", $sformatf(
            "READ PHY[%0d] REG[%0d] = 0x%04h (no prior write, skipping check)",
            phy_addr, reg_addr, rd_data), UVM_LOW)
        end else if (rd_data === miim_phy_regs[reg_addr])
          `uvm_info("MIIM_RD_PASS", $sformatf(
            "PHY[%0d] REG[%0d] read 0x%04h matches model",
            phy_addr, reg_addr, rd_data), UVM_LOW)
        else
          `uvm_error("MIIM_RD_FAIL", $sformatf(
            "PHY[%0d] REG[%0d] read 0x%04h != model 0x%04h",
            phy_addr, reg_addr, rd_data, miim_phy_regs[reg_addr]))
      end
    end
  endtask

endclass