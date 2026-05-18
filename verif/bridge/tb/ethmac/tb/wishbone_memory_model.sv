module wishbone_memory_model (
  wishbone_master_if.Slave wb_if
);

  localparam MEMORY_BASE = 32'h00002000;

  // ------------------------------------------------
  // ACK generation with configurable delay
  // ------------------------------------------------
  logic ack_out;
  int   delay_cnt;

  always_ff @(posedge wb_if.clk or posedge wb_if.rst) begin
    if (wb_if.rst) begin
      ack_out   <= 1'b0;
      delay_cnt <= 0;
    end else if (wb_if.cyc && wb_if.stb && !ack_out) begin
      // Transaction pending, no ACK yet
      if (wb_if.ack_delay == 0) begin
        // Instant ACK (original behavior)
        ack_out <= 1'b1;
      end else if (delay_cnt >= wb_if.ack_delay - 1) begin
        // Delay elapsed
        ack_out   <= 1'b1;
        delay_cnt <= 0;
      end else begin
        delay_cnt <= delay_cnt + 1;
      end
    end else begin
      ack_out   <= 1'b0;
      delay_cnt <= 0;
    end
  end

  assign wb_if.ack = (wb_if.ack_delay == 0) ? (wb_if.cyc & wb_if.stb) : ack_out;
  assign wb_if.err = 1'b0;

  // ------------------------------------------------
  // WRITE path (RX DMA)
  // ------------------------------------------------
  always_ff @(posedge wb_if.clk) begin
    if (wb_if.cyc && wb_if.stb && wb_if.we && wb_if.ack) begin
      int addr;
      addr = wb_if.adr;

      if (wb_if.sel[0]) wb_if.mem[addr + 0] <= wb_if.dat_m[7:0];
      if (wb_if.sel[1]) wb_if.mem[addr + 1] <= wb_if.dat_m[15:8];
      if (wb_if.sel[2]) wb_if.mem[addr + 2] <= wb_if.dat_m[23:16];
      if (wb_if.sel[3]) wb_if.mem[addr + 3] <= wb_if.dat_m[31:24];

      $display("[WB_DMA] WRITE addr=%h data=%h",
               wb_if.adr, wb_if.dat_m);
    end
  end

  // ------------------------------------------------
  // READ path
  // ------------------------------------------------
  always_comb begin
    int addr;
    addr = wb_if.adr;

    wb_if.dat_s = {
      wb_if.mem[addr + 3],
      wb_if.mem[addr + 2],
      wb_if.mem[addr + 1],
      wb_if.mem[addr + 0]
    };
  end

endmodule
