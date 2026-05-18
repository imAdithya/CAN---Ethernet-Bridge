// can_wb_if.sv — 8-bit Wishbone interface for CAN controller master port
// Bridge is master, CAN agent is slave

interface can_wb_if(input logic clk, input logic rst);

  // Address and data
  logic [7:0]  adr;
  logic [7:0]  dat_m;   // Data from master (bridge writes)
  logic [7:0]  dat_s;   // Data from slave (CAN agent responds)

  // Control
  logic        cyc;
  logic        stb;
  logic        we;
  logic        ack;

  // Interrupt signals (driven by TB sequences)
  logic        can_rx_irq;   // CAN RX complete (triggers upstream)
  logic        can_tx_irq;   // CAN TX complete (downstream done)

  // Master port (bridge drives these)
  modport Master (
    output adr, dat_m, cyc, stb, we,
    input  dat_s, ack, can_rx_irq, can_tx_irq
  );

  // Slave port (CAN agent drives these)
  modport Slave (
    input  clk, adr, dat_m, cyc, stb, we,
    output dat_s, ack
  );

  // Monitor port (passive observation)
  modport Monitor (
    input clk, adr, dat_m, dat_s, cyc, stb, we, ack
  );

endinterface : can_wb_if
