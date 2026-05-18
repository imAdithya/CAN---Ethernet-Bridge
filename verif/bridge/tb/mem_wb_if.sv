// mem_wb_if.sv — 32-bit Wishbone interface for ETH/RAM master port
// Bridge is master, Memory agent is slave

interface mem_wb_if(input logic clk, input logic rst);

  // Address and data
  logic [31:0] adr;
  logic [31:0] dat_m;   // Data from master (bridge writes)
  logic [31:0] dat_s;   // Data from slave (memory agent responds)
  logic [3:0]  sel;

  // Control
  logic        cyc;
  logic        stb;
  logic        we;
  logic        ack;

  // Interrupt signals (driven by TB sequences)
  logic        eth_tx_irq;   // ETH TX complete (upstream done)
  logic        eth_rx_irq;   // ETH RX complete (triggers downstream)

  // Master port (bridge drives these)
  modport Master (
    output adr, dat_m, sel, cyc, stb, we,
    input  dat_s, ack, eth_tx_irq, eth_rx_irq
  );

  // Slave port (memory agent drives these)
  modport Slave (
    input  clk, adr, dat_m, sel, cyc, stb, we,
    output dat_s, ack
  );

  // Monitor port
  modport Monitor (
    input clk, adr, dat_m, dat_s, sel, cyc, stb, we, ack
  );

endinterface : mem_wb_if
