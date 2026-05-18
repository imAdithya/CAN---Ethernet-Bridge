`timescale 1ns / 1ns

interface wishbone_slave_if(input logic clk);
  logic rst;
  logic [31:0] adr;
  logic [31:0] dat_m; // Data from master to slave
  logic [31:0] dat_s; // Data from slave to master
  logic        cyc;
  logic        stb;
  logic        we;
  logic  [3:0] sel;
  logic        ack;
  logic        err;

  // Clocking block for UVM driver to drive the DUT's slave port
  clocking driver_cb @(posedge clk);
  output cyc, stb, we, adr, dat_m, sel;
  input  ack, err, dat_s;
endclocking

  // Clocking block for UVM monitor
  clocking monitor_cb @(posedge clk);
    default input #1ns output #1ns;
    input adr, dat_m, dat_s, cyc, stb, we, sel, ack, err;
  endclocking

endinterface