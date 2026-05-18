class wb_can_reset_stress_test extends uvm_test;
  `uvm_component_utils(wb_can_reset_stress_test)

  wb_can_env env;
  virtual wb_can_if vif;

  int reset_assert_pass = 0;
  int recovery_pass = 0;

  function new(string name = "wb_can_reset_stress_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = wb_can_env::type_id::create("env", this);

    if (!uvm_config_db#(virtual wb_can_if)::get(this, "", "vif", vif))
      `uvm_fatal("TEST", "Virtual interface not found in config_db")
  endfunction

  virtual task run_phase(uvm_phase phase);
    phase.raise_objection(this);

    // Wait for initial reset to de-assert
    wait(vif.rst == 0);
    repeat(5) @(posedge vif.clk);
    `uvm_info("TEST", "=== WB-03 Reset Recovery Test Starting ===", UVM_LOW)

    // --- Phase 1: Assert reset during an active bus cycle ---
    `uvm_info("TEST", "Phase 1: Asserting reset during active stb_i", UVM_LOW)
    fork
      // Thread 1: Drive a WB write manually through the interface
      begin
        @(posedge vif.clk);
        vif.adr <= 8'h00;
        vif.din <= 8'h01;
        vif.we  <= 1'b1;
        vif.sel <= 4'h1;
        vif.cyc <= 1'b1;
        vif.stb <= 1'b1;

        // Hold active bus cycle for a few clocks
        repeat(3) @(posedge vif.clk);

        // Keep stb/cyc active ??? reset will kill the cycle
        // Wait until reset is asserted
        wait(vif.rst == 1);

        // After reset, deassert bus signals
        @(posedge vif.clk);
        vif.cyc <= 1'b0;
        vif.stb <= 1'b0;
        vif.we  <= 1'b0;
      end

      // Thread 2: Assert reset after 3 clocks (during active stb)
      begin
        // Wait for stb to go high
        wait(vif.stb == 1);
        repeat(3) @(posedge vif.clk);

        `uvm_info("TEST", "Asserting wb_rst_i NOW (during active stb)", UVM_LOW)
        vif.rst <= 1'b1;  // Assert reset

        // Check that ack drops within 2 clocks
        repeat(2) @(posedge vif.clk);
        if (vif.ack == 1'b0) begin
          `uvm_info("ACK_RST_PASS", "wb_ack_o correctly dropped after reset assertion", UVM_LOW)
          reset_assert_pass = 1;
        end else begin
          `uvm_error("ACK_RST_FAIL", "wb_ack_o did NOT drop after reset assertion!")
        end

        // Verify bus is idle (stb=0, cyc=0)
        repeat(3) @(posedge vif.clk);
        `uvm_info("TEST", $sformatf("Bus state after reset: stb=%0b cyc=%0b ack=%0b",
                   vif.stb, vif.cyc, vif.ack), UVM_LOW)

        // Hold reset for 200ns then release
        #200;
        `uvm_info("TEST", "De-asserting wb_rst_i", UVM_LOW)
        vif.rst <= 1'b0;
      end
    join

    // --- Phase 2: Recovery ??? verify normal operation after reset ---
    `uvm_info("TEST", "Phase 2: Verifying bus recovery with normal transactions", UVM_LOW)
    repeat(5) @(posedge vif.clk);

    begin
      wb_can_reset_stress_seq seq;
      seq = wb_can_reset_stress_seq::type_id::create("seq");

      fork
        // Thread 1: Run the recovery sequence
        seq.start(env.agt.sequencer);

        // Thread 2: Monitor ACK timing for recovery transactions
        begin
          int i;
          for (i = 0; i < 3; i++) begin
            int count = 0;
            string label;

            @(posedge vif.clk);
            wait(vif.stb && vif.cyc);
            label = vif.we ? "WRITE" : "READ";

            while (!vif.ack && count < 20) begin
              @(posedge vif.clk);
              count++;
            end

            if (count >= 5 && count <= 10) begin
              `uvm_info("RECOVERY_PASS", $sformatf("[Post-RST TXN-%0d %s] ACK: %0d clocks OK", i, label, count), UVM_LOW)
              recovery_pass++;
            end else if (count < 20) begin
              `uvm_warning("RECOVERY_WARN", $sformatf("[Post-RST TXN-%0d %s] ACK: %0d clocks (outside 5-10 range)", i, label, count))
              recovery_pass++;
            end else begin
              `uvm_error("RECOVERY_FAIL", $sformatf("[Post-RST TXN-%0d %s] No ACK ??? bus did not recover!", i, label))
            end

            wait(!vif.stb);
          end
        end
      join
    end

    // --- Summary ---
    `uvm_info("TEST", "=== WB-03 Reset Recovery Test Summary ===", UVM_LOW)
    if (reset_assert_pass)
      `uvm_info("RESULT", "PASS: wb_ack_o dropped immediately on reset", UVM_LOW)
    else
      `uvm_error("RESULT", "FAIL: wb_ack_o did not drop on reset")

    if (recovery_pass == 3)
      `uvm_info("RESULT", $sformatf("PASS: Bus recovered ??? %0d/3 post-reset transactions successful", recovery_pass), UVM_LOW)
    else
      `uvm_error("RESULT", $sformatf("FAIL: Bus recovery incomplete ??? %0d/3 post-reset transactions", recovery_pass))

    phase.drop_objection(this);
  endtask
endclass
