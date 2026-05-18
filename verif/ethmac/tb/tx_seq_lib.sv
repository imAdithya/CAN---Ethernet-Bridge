// tb/sequences/tx_seq_lib.sv — TX sequences using raw Wishbone access
`include "uvm_macros.svh"
import uvm_pkg::*;

class tx_min_packet_seq extends uvm_sequence #(wishbone_transaction);
  `uvm_object_utils(tx_min_packet_seq)
  `uvm_declare_p_sequencer(host_sequencer)

  // RAL handle
  // Raw sequences for BD and DMA access (not in register model)
  reg_write_seq write_reg_seq;
  reg_read_seq  read_reg_seq;
  reg_write_seq mem_seq;

  // --- BD Addresses (Not part of RAL) ---
  localparam BD0_STATUS = 32'h400;
  localparam BD0_PTR    = 32'h404;
  localparam TX_BUFFER  = 32'h2000;

  // --- BD Status Flags ---
  localparam BIT_RD    = 16'h8000;
  localparam BIT_IRQ   = 16'h4000;
  localparam BIT_WRAP  = 16'h2000;
  localparam BIT_PAD   = 16'h1000;
  localparam BIT_CRC   = 16'h0800;

  bit [31:0] read_data;

  function new(string name="tx_min_packet_seq");
    super.new(name);
  endfunction

  virtual task body();
    int payload_size = 20;

    // Get RAL model from config_db
    write_reg_seq = reg_write_seq::type_id::create("write_reg_seq");
    read_reg_seq  = reg_read_seq ::type_id::create("read_reg_seq");

    `uvm_info(get_type_name(), "TX-01: Minimum packet (Padding + CRC)", UVM_MEDIUM)

    // 1. Setup MAC via RAL
    write_reg_seq.addr = 32'h20; write_reg_seq.data = 32'd1; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h18; write_reg_seq.data = 32'h0040_0600; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h00; write_reg_seq.data = 32'h0000_A002; write_reg_seq.start(m_sequencer);        // TXEN | PAD | CRC
    write_reg_seq.addr = 32'h04; write_reg_seq.data = 32'hFFFF_FFFF; write_reg_seq.start(m_sequencer);   // Clear interrupts

    // 2. Frontdoor Memory Write via DMA Agent
    begin
      uvm_component comp;
      uvm_sequencer_base dma_seqr;

      comp = uvm_top.find("uvm_test_top.m_env.m_dma_agent.m_sequencer");
      if (comp == null)
        `uvm_fatal("SEQ", "Could not find DMA sequencer")
      if (!$cast(dma_seqr, comp))
        `uvm_fatal("SEQ", "DMA sequencer cast failed")

      mem_seq = reg_write_seq::type_id::create("mem_seq");

      // Write 20 bytes (0xAA) as 5 x 32-bit words
      for (int i = 0; i < payload_size; i += 4) begin
        mem_seq.addr = TX_BUFFER + i;
        mem_seq.data = 32'hAAAA_AAAA;
        mem_seq.start(dma_seqr);
      end

      `uvm_info(get_type_name(), "Frontdoor memory write complete (20 bytes via DMA)", UVM_MEDIUM)
    end

    // 3. Program BD Pointer (raw — not in RAL)
    write_reg_seq.addr = BD0_PTR;
    write_reg_seq.data = TX_BUFFER;
    write_reg_seq.start(m_sequencer);

    // 4. Program BD Status: {Length[15:0], Status[15:0]}
    write_reg_seq.addr = BD0_STATUS;
    write_reg_seq.data = (payload_size << 16) | (BIT_RD | BIT_IRQ | BIT_WRAP | BIT_PAD | BIT_CRC);
    write_reg_seq.start(m_sequencer);

    `uvm_info(get_type_name(), "TX launched...", UVM_MEDIUM)

    // 5. Poll BD for completion (raw — not in RAL)
    for(int i=0; i<1000; i++) begin
      #1000ns;
      read_reg_seq.addr = BD0_STATUS;
      read_reg_seq.start(m_sequencer);
      read_data = read_reg_seq.data;

      if ((read_data & BIT_RD) == 0) begin
        `uvm_info(get_type_name(), $sformatf("PASS: TX complete, BD0_STATUS=0x%08h", read_data), UVM_LOW)
        return;
      end
    end

    `uvm_error(get_type_name(), "TIMEOUT: TX BD Ready bit never cleared")
  endtask
endclass

class tx_max_packet_seq extends uvm_sequence #(wishbone_transaction);
  `uvm_object_utils(tx_max_packet_seq)
  `uvm_declare_p_sequencer(host_sequencer)
  reg_write_seq write_reg_seq;
  reg_read_seq  read_reg_seq;

  localparam BD0_STATUS = 32'h400;
  localparam BD0_PTR    = 32'h404;
  localparam TX_BUFFER  = 32'h2000;

  localparam BIT_RD     = 16'h8000;
  localparam BIT_IRQ    = 16'h4000;
  localparam BIT_WRAP   = 16'h2000;
  localparam BIT_PAD    = 16'h1000;
  localparam BIT_CRC    = 16'h0800;

  function new(string name="tx_max_packet_seq");
    super.new(name);
  endfunction

  virtual task body();
    int data_length = 1514; 
    logic [31:0] status_val;
    logic [31:0] int_val;
    write_reg_seq = reg_write_seq::type_id::create("write_reg_seq");
    read_reg_seq  = reg_read_seq::type_id::create("read_reg_seq");

    `uvm_info(get_type_name(), "TX-02: Max Packet (Half Duplex)", UVM_MEDIUM)

    // 1. Setup via RAL
    write_reg_seq.addr = 32'h0C; write_reg_seq.data = 32'h12; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h10; write_reg_seq.data = 32'h0C; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h14; write_reg_seq.data = 32'h12; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h1C; write_reg_seq.data = 32'h000F_003F; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h20; write_reg_seq.data = 32'd1; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h18; write_reg_seq.data = 32'h0040_0600; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h00; write_reg_seq.data = 32'h0000_A002; write_reg_seq.start(m_sequencer);        // Half Duplex, CRC, PAD
    write_reg_seq.addr = 32'h04; write_reg_seq.data = 32'hFFFF_FFFF; write_reg_seq.start(m_sequencer);

    // 2. Backdoor Memory Write
    if (p_sequencer.mem_vif == null)
       `uvm_fatal("SEQ", "Memory Interface (mem_vif) is NULL!")

    for (int i = 0; i < data_length; i++) begin
       p_sequencer.mem_vif.preload_byte(TX_BUFFER + i, (i & 8'hFF)); 
    end
    `uvm_info("SEQ", "Memory Preloaded.", UVM_HIGH)

    // 3. Setup BD (raw)
    write_reg_seq.addr = BD0_PTR;    write_reg_seq.data = TX_BUFFER; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = BD0_STATUS;
    write_reg_seq.data = (data_length << 16) | (BIT_RD | BIT_IRQ | BIT_WRAP | BIT_CRC);
    write_reg_seq.start(m_sequencer);

    `uvm_info(get_type_name(), "TX Launched. Polling for completion...", UVM_MEDIUM)

    // 4. Poll
    for(int i=0; i<5000; i++) begin
      #1000ns;
      read_reg_seq.addr = BD0_STATUS;
      read_reg_seq.start(m_sequencer);
      status_val = read_reg_seq.data;
      
      if ((status_val & BIT_RD) == 0) begin
         `uvm_info(get_type_name(), $sformatf("PASS: TX complete. BD Status=0x%08h", status_val), UVM_NONE)
         return;
      end
    end

    // Failure Debugging — read INT_SOURCE via RAL
    begin
      logic [31:0] rdata;
      read_reg_seq.addr = 32'h04; read_reg_seq.start(m_sequencer); rdata = read_reg_seq.data;
      int_val = rdata;
    end
    `uvm_error(get_type_name(), $sformatf("TIMEOUT. BD=0x%08h, INT_SOURCE=0x%08h", status_val, int_val))
  endtask
endclass

class tx_full_ring_seq extends uvm_sequence #(wishbone_transaction);
  `uvm_object_utils(tx_full_ring_seq)
  `uvm_declare_p_sequencer(host_sequencer)
  reg_write_seq write_reg_seq;
  reg_read_seq  read_reg_seq;

  localparam BD_BASE    = 32'h400;
  localparam BUF0       = 32'h2000;
  localparam BUF1       = 32'h2800;
  localparam BUF2       = 32'h3000;
  localparam BUF3       = 32'h3800;

  localparam BIT_RD     = 16'h8000;
  localparam BIT_IRQ    = 16'h4000;
  localparam BIT_WRAP   = 16'h2000;
  localparam BIT_PAD    = 16'h1000;
  localparam BIT_CRC    = 16'h0800;

  function new(string name="tx_full_ring_seq");
    super.new(name);
  endfunction

  virtual task body();
    int pkt_sizes[4] = '{20, 400, 1000, 1514}; 
    int buf_addrs[4] = '{BUF0, BUF1, BUF2, BUF3};
    logic [31:0] bd_status_addr;
    logic [31:0] bd_ptr_addr;
    logic [31:0] status_val;
    logic [31:0] final_bd_status;
    write_reg_seq = reg_write_seq::type_id::create("write_reg_seq");
    read_reg_seq  = reg_read_seq::type_id::create("read_reg_seq");

    `uvm_info(get_type_name(), "TX-03: Back-to-Back Ring Test (4 Packets)", UVM_MEDIUM)

    // 1. Configure MAC via RAL
    write_reg_seq.addr = 32'h0C; write_reg_seq.data = 32'h12; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h10; write_reg_seq.data = 32'h0C; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h14; write_reg_seq.data = 32'h12; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h20; write_reg_seq.data = 32'd4; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h18; write_reg_seq.data = 32'h0040_0600; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h00; write_reg_seq.data = 32'h0000_A003; write_reg_seq.start(m_sequencer);        // Half Duplex, CRC, PAD, TXEN+RXEN
    write_reg_seq.addr = 32'h04; write_reg_seq.data = 32'hFFFF_FFFF; write_reg_seq.start(m_sequencer);

    // 2. Preload Memory (Backdoor)
    if (p_sequencer.mem_vif == null) `uvm_fatal("SEQ", "mem_vif is NULL")

    for (int k=0; k<4; k++) begin
        for (int i=0; i<pkt_sizes[k]; i++) begin
            p_sequencer.mem_vif.preload_byte(buf_addrs[k] + i, (k*16 + i) & 8'hFF); 
        end
    end
    `uvm_info("SEQ", "Memory initialized for 4 buffers.", UVM_HIGH)

    // 3. Program Buffer Descriptors (raw — BDs not in RAL)
    for (int k=0; k<4; k++) begin
        bd_status_addr = BD_BASE + (k * 8);
        bd_ptr_addr    = BD_BASE + (k * 8) + 4;

        write_reg_seq.addr = bd_ptr_addr;
        write_reg_seq.data = buf_addrs[k];
        write_reg_seq.start(m_sequencer);

        status_val = (pkt_sizes[k] << 16) | BIT_RD | BIT_IRQ | BIT_PAD | BIT_CRC;
        if (k == 3) status_val |= BIT_WRAP;

        write_reg_seq.addr = bd_status_addr;
        write_reg_seq.data = status_val;
        write_reg_seq.start(m_sequencer);
        
        `uvm_info("SEQ", $sformatf("Armed BD%0d: Addr=0x%h, Len=%0d, WRAP=%0d", 
                  k, bd_status_addr, pkt_sizes[k], (k==3)), UVM_HIGH)
    end

    `uvm_info(get_type_name(), "All 4 BDs ready. Transmission should be active.", UVM_MEDIUM)

    // 4. Poll for BD3 completion
    bd_status_addr = BD_BASE + (3 * 8); 

    for(int i=0; i<8000; i++) begin
      #1000ns;
      read_reg_seq.addr = bd_status_addr;
      read_reg_seq.start(m_sequencer);
      final_bd_status = read_reg_seq.data;
      
      if ((final_bd_status & BIT_RD) == 0) begin
         `uvm_info(get_type_name(), "PASS: Chain Complete. Last BD Ready bit cleared.", UVM_NONE)
         
         read_reg_seq.addr = BD_BASE;
         read_reg_seq.start(m_sequencer);
         if ((read_reg_seq.data & BIT_RD) != 0)
             `uvm_error("SEQ", "Error: BD3 finished but BD0 is still active? Impossible.")
             
         return;
      end
    end

    `uvm_error(get_type_name(), "TIMEOUT: Back-to-Back ring transmission failed.")
  endtask
endclass

class tx_random_seq extends uvm_sequence #(wishbone_transaction);
  `uvm_object_utils(tx_random_seq)
  `uvm_declare_p_sequencer(host_sequencer)
  reg_write_seq write_reg_seq;
  reg_read_seq  read_reg_seq;

  localparam BD0_STATUS = 32'h400;
  localparam BD0_PTR    = 32'h404;

  localparam BIT_RD     = 16'h8000;
  localparam BIT_IRQ    = 16'h4000;
  localparam BIT_WRAP   = 16'h2000;
  localparam BIT_PAD    = 16'h1000;
  localparam BIT_CRC    = 16'h0800;

  // --- Random Variables ---
  rand bit [31:0] buf_addr;
  rand int unsigned len;
  rand bit        en_pad;
  rand bit        en_crc;

  constraint c_addr {
    buf_addr inside {[32'h2000 : 32'h7000]};
    buf_addr % 4 dist { 0:=70, [1:3]:=30 };
  }

  constraint c_len {
    len dist {
      [1:20]     := 10,
      [21:59]    := 20,
      [60:1000]  := 40,
      [1001:1513]:= 20,
      1514       := 10
    };
  }

  function new(string name="tx_random_seq");
    super.new(name);
  endfunction

  virtual task body();
    logic [31:0] bd_val;
    logic [31:0] status_read;
    int iterations = 50;
    write_reg_seq = reg_write_seq::type_id::create("write_reg_seq");
    read_reg_seq  = reg_read_seq::type_id::create("read_reg_seq");

    `uvm_info(get_type_name(), $sformatf("Starting TX-04: Half Duplex Random Test (%0d iter)", iterations), UVM_MEDIUM)

    // 1. Configure MAC via RAL
    write_reg_seq.addr = 32'h0C; write_reg_seq.data = 32'h12; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h10; write_reg_seq.data = 32'h0C; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h14; write_reg_seq.data = 32'h12; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h1C; write_reg_seq.data = 32'h000F_003F; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h20; write_reg_seq.data = 32'd1; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h18; write_reg_seq.data = 32'h0040_0600; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h00; write_reg_seq.data = 32'h0000_A002; write_reg_seq.start(m_sequencer);        // Half Duplex, CRC, PAD
    write_reg_seq.addr = 32'h04; write_reg_seq.data = 32'hFFFF_FFFF; write_reg_seq.start(m_sequencer);

    // 2. Random Loop
    for(int i=1; i<=iterations; i++) begin
      
      if(!this.randomize()) `uvm_fatal("SEQ", "Randomization failed");

      `uvm_info("SEQ", $sformatf("[Iter %0d] Addr=0x%h Len=%0d Pad=%b CRC=%b", 
                                 i, buf_addr, len, en_pad, en_crc), UVM_MEDIUM)

      // A. Frontdoor Memory Write via DMA Agent
      begin
        uvm_component comp;
        uvm_sequencer_base dma_seqr;
        reg_write_seq dma_wr;
        int b;
        int word_addr;
        int byte_off;
        logic [31:0] wdata;

        comp = uvm_top.find("uvm_test_top.m_env.m_dma_agent.m_sequencer");
        if (comp == null) `uvm_fatal("SEQ", "Could not find DMA sequencer")
        if (!$cast(dma_seqr, comp)) `uvm_fatal("SEQ", "DMA sequencer cast failed")

        dma_wr = reg_write_seq::type_id::create("dma_wr");

        b = 0;
        while (b < len) begin
          word_addr = (buf_addr + b) & 32'hFFFF_FFFC;
          wdata = 32'h0;

          for (int lane = 0; lane < 4; lane++) begin
            byte_off = (buf_addr + b) & 2'h3;
            if (byte_off == lane && b < len) begin
              case (lane)
                0: wdata[7:0]   = (b & 8'hFF);
                1: wdata[15:8]  = (b & 8'hFF);
                2: wdata[23:16] = (b & 8'hFF);
                3: wdata[31:24] = (b & 8'hFF);
              endcase
              b++;
            end
          end

          dma_wr.addr = word_addr;
          dma_wr.data = wdata;
          dma_wr.start(dma_seqr);
        end
      end

      // B. Program BD (raw)
      write_reg_seq.addr = BD0_PTR;
      write_reg_seq.data = buf_addr; 
      write_reg_seq.start(m_sequencer);

      bd_val = (len << 16) | BIT_RD | BIT_IRQ | BIT_WRAP;
      if (en_pad) bd_val |= BIT_PAD;
      if (en_crc) bd_val |= BIT_CRC;

      write_reg_seq.addr = BD0_STATUS;
      write_reg_seq.data = bd_val;
      write_reg_seq.start(m_sequencer);

      // C. Poll for Completion
      for(int t=0; t<5000; t++) begin
        #1000ns;
        read_reg_seq.addr = BD0_STATUS;
        read_reg_seq.start(m_sequencer);
        status_read = read_reg_seq.data;

        if((status_read & BIT_RD) == 0) break;
        
        if(t == 4999) 
          `uvm_error("SEQ", $sformatf("TIMEOUT on Iteration %0d (Len=%0d)", i, len))
      end
    end

    `uvm_info(get_type_name(), "TX-04 Half Duplex Random Test Finished.", UVM_MEDIUM)
  endtask
endclass

class tx_huge_packet_seq extends uvm_sequence #(wishbone_transaction);
  `uvm_object_utils(tx_huge_packet_seq)
  `uvm_declare_p_sequencer(host_sequencer)
  reg_write_seq write_reg_seq;
  reg_read_seq  read_reg_seq;

  localparam BD0_STATUS = 32'h400;
  localparam BD0_PTR    = 32'h404;
  localparam TX_BUFFER  = 32'h2000;

  localparam BIT_RD     = 16'h8000;
  localparam BIT_IRQ    = 16'h4000;
  localparam BIT_WRAP   = 16'h2000; 
  localparam BIT_PAD    = 16'h1000;
  localparam BIT_CRC    = 16'h0800;

  function new(string name="tx_huge_packet_seq");
    super.new(name);
  endfunction

  virtual task body();
    int data_length = 2500; 
    logic [31:0] status_val;
    write_reg_seq = reg_write_seq::type_id::create("write_reg_seq");
    read_reg_seq  = reg_read_seq::type_id::create("read_reg_seq");

    `uvm_info(get_type_name(), $sformatf("TX-05: Huge Packet (Len=%0d) Half Duplex", data_length), UVM_MEDIUM)

    // 1. Setup via RAL — HUGEN enabled
    write_reg_seq.addr = 32'h0C; write_reg_seq.data = 32'h12; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h10; write_reg_seq.data = 32'h0C; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h14; write_reg_seq.data = 32'h12; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h1C; write_reg_seq.data = 32'h000F_003F; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h20; write_reg_seq.data = 32'd1; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h18; write_reg_seq.data = 32'h0040_0600; write_reg_seq.start(m_sequencer);

    // MODER: PAD | HUGEN | CRC | TXEN | RXEN = 0xE003
    write_reg_seq.addr = 32'h00; write_reg_seq.data = 32'h0000_E003; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h04; write_reg_seq.data = 32'hFFFF_FFFF; write_reg_seq.start(m_sequencer);

    // 2. Backdoor Memory Write
    if (p_sequencer.mem_vif == null)
       `uvm_fatal("SEQ", "Memory Interface (mem_vif) is NULL!")

    for (int i = 0; i < data_length; i++) begin
       p_sequencer.mem_vif.preload_byte(TX_BUFFER + i, (i & 8'hFF)); 
    end
    `uvm_info("SEQ", "Huge Memory Block Preloaded.", UVM_HIGH)

    // 3. Setup BD (raw)
    write_reg_seq.addr = BD0_PTR;    write_reg_seq.data = TX_BUFFER; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = BD0_STATUS;
    write_reg_seq.data = (data_length << 16) | (BIT_RD | BIT_IRQ | BIT_WRAP | BIT_CRC);
    write_reg_seq.start(m_sequencer);

    `uvm_info(get_type_name(), "TX Launched. Polling for completion...", UVM_MEDIUM)

    // 4. Poll
    for(int i=0; i<8000; i++) begin
      #1000ns;
      read_reg_seq.addr = BD0_STATUS;
      read_reg_seq.start(m_sequencer);
      status_val = read_reg_seq.data;
      
      if ((status_val & BIT_RD) == 0) begin
         `uvm_info(get_type_name(), $sformatf("PASS: TX complete. BD Status=0x%08h", status_val), UVM_NONE)
         return;
      end
    end

    `uvm_error(get_type_name(), "TIMEOUT: Huge Packet transmission stuck in Half Duplex.")
  endtask
endclass

class tx_broad_multi_seq extends uvm_sequence #(wishbone_transaction);
  `uvm_object_utils(tx_broad_multi_seq)
  `uvm_declare_p_sequencer(host_sequencer)
  reg_write_seq write_reg_seq;
  reg_read_seq  read_reg_seq;

  localparam BD0_STATUS = 32'h400;
  localparam BD0_PTR    = 32'h404;
  localparam TX_BUFFER_BCAST = 32'h2000;
  localparam TX_BUFFER_MCAST = 32'h2800;

  localparam BIT_RD     = 16'h8000;
  localparam BIT_IRQ    = 16'h4000;
  localparam BIT_WRAP   = 16'h2000;
  localparam BIT_PAD    = 16'h1000;
  localparam BIT_CRC    = 16'h0800;

  function new(string name="tx_broad_multi_seq");
    super.new(name);
  endfunction

  virtual task body();
    int pkt_len = 100;
    logic [7:0] byte_data;
    write_reg_seq = reg_write_seq::type_id::create("write_reg_seq");
    read_reg_seq  = reg_read_seq::type_id::create("read_reg_seq");

    `uvm_info(get_type_name(), "TX-06: Broadcast & Multicast Test (Half Duplex)", UVM_MEDIUM)

    // 1. Init via RAL
    write_reg_seq.addr = 32'h0C; write_reg_seq.data = 32'h12; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h10; write_reg_seq.data = 32'h0C; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h14; write_reg_seq.data = 32'h12; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h1C; write_reg_seq.data = 32'h000F_003F; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h20; write_reg_seq.data = 32'd1; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h18; write_reg_seq.data = 32'h0040_0600; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h00; write_reg_seq.data = 32'h0000_A003; write_reg_seq.start(m_sequencer);        // Half Duplex, CRC, PAD, TXEN+RXEN
    write_reg_seq.addr = 32'h04; write_reg_seq.data = 32'hFFFF_FFFF; write_reg_seq.start(m_sequencer);

    if (p_sequencer.mem_vif == null) `uvm_fatal("SEQ", "mem_vif is NULL")

    // =======================================================
    // PACKET 1: BROADCAST (FF:FF:FF:FF:FF:FF)
    // =======================================================
    `uvm_info("SEQ", "Preparing BROADCAST Packet...", UVM_MEDIUM)
    
    for (int i=0; i<pkt_len; i++) begin
        if (i < 6) byte_data = 8'hFF;
        else if (i < 12) byte_data = 8'hAA;
        else byte_data = (i & 8'hFF);
        p_sequencer.mem_vif.preload_byte(TX_BUFFER_BCAST + i, byte_data);
    end

    write_reg_seq.addr = BD0_PTR;    write_reg_seq.data = TX_BUFFER_BCAST; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = BD0_STATUS; 
    write_reg_seq.data = (pkt_len << 16) | BIT_RD | BIT_IRQ | BIT_WRAP | BIT_PAD | BIT_CRC;
    write_reg_seq.start(m_sequencer);
    
    poll_completion("BROADCAST");

    // =======================================================
    // PACKET 2: MULTICAST (01:00:5E:...)
    // =======================================================
    `uvm_info("SEQ", "Preparing MULTICAST Packet...", UVM_MEDIUM)
    
    for (int i=0; i<pkt_len; i++) begin
        if (i == 0)      byte_data = 8'h01; 
        else if (i == 1) byte_data = 8'h00;
        else if (i == 2) byte_data = 8'h5E;
        else if (i < 6)  byte_data = 8'h00;
        else if (i < 12) byte_data = 8'hBB;
        else byte_data = (i & 8'hFF);
        p_sequencer.mem_vif.preload_byte(TX_BUFFER_MCAST + i, byte_data);
    end

    write_reg_seq.addr = BD0_PTR;    write_reg_seq.data = TX_BUFFER_MCAST; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = BD0_STATUS; 
    write_reg_seq.data = (pkt_len << 16) | BIT_RD | BIT_IRQ | BIT_WRAP | BIT_PAD | BIT_CRC;
    write_reg_seq.start(m_sequencer);
    
    poll_completion("MULTICAST");

    `uvm_info(get_type_name(), "TX-06 Test Finished Successfully.", UVM_MEDIUM)
  endtask

  // Helper Task for Polling
  task poll_completion(string pkt_type);
    for(int i=0; i<2000; i++) begin
      #1000ns;
      read_reg_seq.addr = BD0_STATUS;
      read_reg_seq.start(m_sequencer);
      if ((read_reg_seq.data & BIT_RD) == 0) begin
         `uvm_info("SEQ", $sformatf("PASS: %s TX Complete.", pkt_type), UVM_MEDIUM)
         return;
      end
    end
    `uvm_error("SEQ", $sformatf("TIMEOUT: %s Packet stuck.", pkt_type))
  endtask

endclass

class tx_dly_crc_seq extends uvm_sequence #(wishbone_transaction);
  `uvm_object_utils(tx_dly_crc_seq)
  `uvm_declare_p_sequencer(host_sequencer)
  reg_write_seq write_reg_seq;
  reg_read_seq  read_reg_seq;

  localparam BD0_STATUS = 32'h400;
  localparam BD0_PTR    = 32'h404;
  localparam TX_BUFFER  = 32'h2000;

  localparam BIT_RD     = 16'h8000;
  localparam BIT_IRQ    = 16'h4000;
  localparam BIT_WRAP   = 16'h2000; 
  localparam BIT_PAD    = 16'h1000;
  localparam BIT_CRC    = 16'h0800;

  rand int unsigned pkt_len;
  constraint c_len { pkt_len inside {[20:1000]}; }

  function new(string name="tx_dly_crc_seq");
    super.new(name);
  endfunction

  virtual task body();
    logic [31:0] status_val;
    int iterations = 5;
    write_reg_seq = reg_write_seq::type_id::create("write_reg_seq");
    read_reg_seq  = reg_read_seq::type_id::create("read_reg_seq");

    `uvm_info(get_type_name(), "TX-07: Delayed CRC Test (Half Duplex)", UVM_MEDIUM)

    // 1. Setup via RAL — DLYCRCEN enabled
    write_reg_seq.addr = 32'h0C; write_reg_seq.data = 32'h12; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h10; write_reg_seq.data = 32'h0C; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h14; write_reg_seq.data = 32'h12; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h1C; write_reg_seq.data = 32'h000F_003F; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h20; write_reg_seq.data = 32'd1; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h18; write_reg_seq.data = 32'h0040_0600; write_reg_seq.start(m_sequencer);

    // MODER: PAD | CRCEN | DLYCRCEN | TXEN | RXEN = 0xB003
    write_reg_seq.addr = 32'h00; write_reg_seq.data = 32'h0000_B003; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h04; write_reg_seq.data = 32'hFFFF_FFFF; write_reg_seq.start(m_sequencer);

    if (p_sequencer.mem_vif == null) `uvm_fatal("SEQ", "mem_vif is NULL")

    // 2. Loop for various lengths
    for(int i=1; i<=iterations; i++) begin
        if(!this.randomize()) `uvm_fatal("SEQ", "Randomization failed");

        `uvm_info("SEQ", $sformatf("[Iter %0d] Sending Packet Len=%0d with DLYCRCEN", i, pkt_len), UVM_MEDIUM)

        // A. Preload Memory
        for (int k=0; k<pkt_len; k++) begin
           p_sequencer.mem_vif.preload_byte(TX_BUFFER + k, (k & 8'hFF)); 
        end

        // B. Setup BD (raw)
        write_reg_seq.addr = BD0_PTR;    write_reg_seq.data = TX_BUFFER; write_reg_seq.start(m_sequencer);
        write_reg_seq.addr = BD0_STATUS; 
        write_reg_seq.data = (pkt_len << 16) | BIT_RD | BIT_IRQ | BIT_WRAP | BIT_PAD | BIT_CRC;
        write_reg_seq.start(m_sequencer);

        // C. Poll
        poll_completion(i);
    end

    `uvm_info(get_type_name(), "TX-07 Test Finished Successfully.", UVM_MEDIUM)
  endtask

  task poll_completion(int iter);
    for(int t=0; t<2000; t++) begin
      #1000ns;
      read_reg_seq.addr = BD0_STATUS;
      read_reg_seq.start(m_sequencer);
      if ((read_reg_seq.data & BIT_RD) == 0) begin
         `uvm_info("SEQ", $sformatf("PASS: Iter %0d Complete.", iter), UVM_HIGH)
         return;
      end
    end
    `uvm_error("SEQ", $sformatf("TIMEOUT: Iter %0d stuck.", iter))
  endtask

endclass