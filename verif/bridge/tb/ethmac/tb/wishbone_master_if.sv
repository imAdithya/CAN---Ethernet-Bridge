// tb/interfaces/wishbone_master_if.sv
`timescale 1ns / 1ns

interface wishbone_master_if (
  input logic clk,
  input logic rst
);
  // ------------------------------------------------------------
  // Wishbone signals
  // ------------------------------------------------------------
  logic [31:0] adr;
  logic [31:0] dat_m; // Data from master (DUT)
  logic [31:0] dat_s; // Data to master (memory)
  logic        cyc;
  logic        stb;
  logic        we;
  logic [3:0]  sel;
  logic        ack;
  logic        err;

  // Interrupt output from DUT
  logic        int_o;

  // ------------------------------------------------------------
  // SHARED MEMORY STORAGE
  // ------------------------------------------------------------
  // We place the memory here so both the Sequence (Backdoor) 
  // and the Module (Hardware) can access it.
  logic [7:0] mem[65536]; 

  // Configurable ACK delay for DMA reads (0 = instant, >0 = delayed)
  int ack_delay = 0;

  // ------------------------------------------------------------
  // BACKDOOR TASKS (Defined HERE, inside the interface)
  // ------------------------------------------------------------
  task automatic preload_byte(
    input int unsigned addr,
    input byte          data
  );
    mem[addr] = data;
  endtask

  task automatic preload_word(
    input int unsigned addr,
    input logic [31:0]  data,
    input logic [3:0]   sel
  );
    if (sel[0]) mem[addr + 0] = data[7:0];
    if (sel[1]) mem[addr + 1] = data[15:8];
    if (sel[2]) mem[addr + 2] = data[23:16];
    if (sel[3]) mem[addr + 3] = data[31:24];
  endtask

  function byte read_byte(input int unsigned addr);
    return mem[addr];
  endfunction

  // ------------------------------------------------------------
  // Modports
  // ------------------------------------------------------------

  // DUT is the MASTER
  modport Master (
    output adr, dat_m, cyc, stb, we, sel,
    input  dat_s, ack, err, clk, rst
  );

  // Memory model is the SLAVE
  // FIX: pass 'mem' by reference so the model can read/write it
  modport Slave (
    input  adr, dat_m, cyc, stb, we, sel, clk, rst, ack_delay,
    output dat_s, ack, err,
    ref    mem
  );

  // ------------------------------------------------------------
  // Clocking block (for monitors)
  // ------------------------------------------------------------
  clocking monitor_cb @(posedge clk);
    default input #1ns output #1ns;
    input adr, dat_m, dat_s, cyc, stb, we, sel, ack, err;
  endclocking

endinterface