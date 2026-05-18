`timescale 1ns/10ps

// CAN Bus Interface (Renamed from can_bus_if to avoid conflicts)
interface cb_if(input bit clk, input bit rst);

  // CAN bus signals
  logic can_rx;    // Driven by agent into DUT rx_i
  logic can_tx;    // Observed from DUT tx_o
  logic can_bus;   // Calculated shared bus state (can_rx & can_tx)

  // Status signals from DUT
  logic bus_off_on;
  logic irq_on;

  // Configurable bit time in clock cycles
  // BTR0=0, BTR1=0x25 -> 10 tq/bit. 1 tq = 2 clks. Total = 20 clks per bit.
  int unsigned bit_time_clks = 20;

  // Clocking block for driver (Active mode)
  clocking drv_cb @(posedge clk);
    default input #1ns output #1ns;
    output can_rx;
    input  can_tx;
  endclocking

  // Clocking block for monitor (Passive mode)
  clocking mon_cb @(posedge clk);
    default input #1ns output #1ns;
    input  can_tx;
    input  can_rx;
  endclocking

  modport driver (clocking drv_cb, input clk, input rst);
  modport monitor (clocking mon_cb, input clk, input rst);

endinterface
