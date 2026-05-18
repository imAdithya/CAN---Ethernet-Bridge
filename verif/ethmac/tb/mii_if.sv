// tb/interfaces/mii_if.sv
`timescale 1ns / 1ns

interface mii_if(input logic tx_clk, input logic rx_clk);
  // Configurable MII clock half-periods (writable from sequences)
  // Default: 20ns = 25 MHz = 100 Mbps
  // 10 Mbps: 200ns = 2.5 MHz
  int mii_tx_half_period = 20;
  int mii_rx_half_period = 20;
  // --- Standard MII Signals ---
  logic [3:0] txd;
  logic       tx_en;
  logic       tx_err;

  logic [3:0] rxd;
  logic       rx_dv;
  logic       rx_err;

  logic       crs;
  logic       col;

  // --- Management Interface (MIIM) ---
  logic       mdc;
  wire        mdio; 

  // --- Testbench Helper Signals ---
  logic       phy_mdo; 
  logic       phy_oe;  

  assign mdio = phy_oe ? phy_mdo : 1'bz;

  // --- Signals from DUT ---
  logic       mdio_o;  
  logic       mdio_oe; 
  logic       mdio_i;  

  // Clocking block for Monitor (TX domain)
  clocking tx_cb @(posedge tx_clk);
    default input #1ns output #1ns;
    input txd, tx_en, tx_err;
    input mdc, mdio, mdio_oe; 
  endclocking

  // Clocking block for Driver (RX domain)
  clocking rx_cb @(posedge rx_clk);
    default input #1ns output #1ns;
    output rxd, rx_dv, rx_err, crs, col;
  endclocking

  // -------------------------------------------------------
  // [CRITICAL ADDITION] Monitor Clocking Block (RX domain)
  // -------------------------------------------------------
  // This allows the monitor to sample driver outputs as INPUTS
  clocking mon_cb @(posedge rx_clk);
    default input #1ns output #1ns;
    input rxd, rx_dv, rx_err, crs, col;
    input txd, tx_en, tx_err;
  endclocking

endinterface