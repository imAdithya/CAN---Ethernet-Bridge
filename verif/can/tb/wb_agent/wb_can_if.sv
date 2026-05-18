interface wb_can_if(input bit clk, input bit rst);
  logic [7:0] adr;
  logic [7:0] din;
  logic [7:0] dout;
  logic       we;
  logic       stb;
  logic       cyc;
  logic       ack;
  logic [3:0] sel;
  logic       clkout;

  // Clocking block for timing accuracy in Questa
  clocking cb @(posedge clk);
    default input #1ns output #1ns;
    output adr, din, we, stb, cyc, sel;
    input  dout, ack, clkout;
  endclocking
  // ---------------------------------------------------------
  // SYSTEMVERILOG ASSERTIONS (SVA) for Wishbone Protocol
  // ---------------------------------------------------------

  // 1. STB implies CYC: Strobe can only be high if Cycle is high
  property p_stb_implies_cyc;
    @(posedge clk) disable iff(rst)
    stb |-> cyc;
  endproperty
  assert_stb_implies_cyc: assert property(p_stb_implies_cyc)
    else $error("SVA Protocol Violation: stb is high but cyc is low");

  // 2. ACK constraint: ACK should only occur during an active cycle & strobe
  property p_ack_needs_stb_cyc;
    @(posedge clk) disable iff(rst)
    ack |-> (cyc && stb);
  endproperty
  assert_ack_needs_stb_cyc: assert property(p_ack_needs_stb_cyc)
    else $error("SVA Protocol Violation: ack asserted without an active cycle and strobe");

  // 3. Stable signals: Address and WE must be stable during an active cycle until ACK
  property p_stable_addr_we;
    @(posedge clk) disable iff(rst)
    (cyc && stb && !ack) |=> ($stable(adr) && $stable(we));
  endproperty
  assert_stable_addr_we: assert property(p_stable_addr_we)
    else $error("SVA Protocol Violation: Address or WE changed during active cycle before ACK");

  // 4. Timeouts: If STB is high, an ACK must arrive eventually (e.g., within 20 clocks)
  property p_ack_timeout;
    @(posedge clk) disable iff(rst)
    (cyc && stb && !ack) |-> ##[1:20] ack;
  endproperty
  assert_ack_timeout: assert property(p_ack_timeout)
    else $error("SVA Protocol Violation: Timeout waiting for ACK response (exceeded 20 clocks)");

endinterface