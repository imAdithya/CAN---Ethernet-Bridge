class wb_can_clk_div_seq extends uvm_sequence#(wb_can_trans);
  `uvm_object_utils(wb_can_clk_div_seq)

  virtual wb_can_if vif;

  function new(string name = "wb_can_clk_div_seq");
    super.new(name);
  endfunction

  virtual task body();
    wb_can_trans req;
    int clkout_toggles;
    int expected_toggles;
    int measured_ratio;
    string ratio_str;

    if (!uvm_config_db#(virtual wb_can_if)::get(null, "uvm_test_top.env.agt.driver", "vif", vif)) begin
      `uvm_fatal(get_name(), "Could not get virtual interface vif from config_db")
    end

    `uvm_info(get_name(), "--- REG-07: STARTING CLOCK DIVIDER VERIFICATION ---", UVM_LOW)

    // Setup: Reset Mode, Base or PeliCAN doesn't matter, CDR is at 0x1F in both
    // Actually, CDR is only writable in Reset Mode per SJA1000 specs!
    `uvm_info(get_name(), "Ensuring Core is in Reset Mode...", UVM_LOW)
    req = wb_can_trans::type_id::create("req");
    start_item(req); req.addr = 8'h00; req.we = 1'b1; req.data = 8'h01; finish_item(req);

    // Loop through all 8 divider ratios
    for (int i = 0; i < 8; i++) begin
      `uvm_info(get_name(), $sformatf("Testing Divider Register CDR[2:0] = 3'b%03b", i[2:0]), UVM_LOW)
      
      // Write the new divider value
      start_item(req); req.addr = 8'h1F; req.we = 1'b1; req.data = {5'h00, i[2:0]}; finish_item(req);
      
      // Wait a few clocks for the new divider to physically lock inside the RTL
      @(posedge vif.clk);
      @(posedge vif.clk);
      @(posedge vif.clk);

      clkout_toggles = 0;
      
      // We will count how many times clkout toggles high over exactly 1400 system clocks
      // 1400 is chosen because it's cleanly divisible by all target ratios (2, 4, 6, 8, 10, 12, 14, 1)
      fork
        // Thread 1: The Measurement Window
        begin
          repeat(1400) @(posedge vif.clk);
        end
        
        // Thread 2: The Toggle Counter
        begin
          forever begin
            @(posedge vif.clkout);
            clkout_toggles++;
          end
        end
      join_any // Stop counting as soon as Thread 1 hits 1400 system clocks
      disable fork; // Kill the forever loop

      // Mathematically evaluate the RTL's performance against the literal SJA1000 datasheet
      // The datasheet says CDR[2:0] defines "f_clkout = f_osc / (2 * (CDR[2:0] + 1))" for 0..6
      // Except value 7, which explicitly bypasses the divider: "f_clkout = f_osc" 
      
      if (i == 7) begin
        expected_toggles = 1400; // Div by 1
        ratio_str = "/ 1";
      end else begin
        expected_toggles = 1400 / (2 * (i + 1));
        ratio_str = $sformatf("/ %0d", (2 * (i + 1)));
      end

      `uvm_info(get_name(), $sformatf("Measured %0d clkout toggles over 1400 clk_i cycles (Hardware Ratio: %s)", clkout_toggles, ratio_str), UVM_LOW)

      // Allow a small +- 1 tolerance for sampling edge jitter aligning with our measurement window
      if (clkout_toggles < expected_toggles - 1 || clkout_toggles > expected_toggles + 1) begin
         `uvm_error("DIV_FAIL", $sformatf("CDR=%0d FAILED! Expected %0d toggles, Got %0d", i, expected_toggles, clkout_toggles))
      end else begin
         `uvm_info(get_name(), $sformatf("CDR=%0d PASSED!", i), UVM_HIGH)
      end

    end

    `uvm_info(get_name(), "--- REG-07: CLOCK DIVIDER VERIFICATION COMPLETE ---", UVM_LOW)

  endtask
endclass
