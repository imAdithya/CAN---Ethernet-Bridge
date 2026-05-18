class wb_can_burst_like_test extends uvm_test;
  `uvm_component_utils(wb_can_burst_like_test)

  wb_can_env env;
  virtual wb_can_if vif;

  // Expected write values for integrity check
  logic [7:0] exp_data [logic [7:0]];

  // Timing tracking
  int ack_latencies[$];
  int timing_errors = 0;

  function new(string name = "wb_can_burst_like_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = wb_can_env::type_id::create("env", this);

    if (!uvm_config_db#(virtual wb_can_if)::get(this, "", "vif", vif))
      `uvm_fatal("TEST", "Virtual interface not found in config_db")
  endfunction

  virtual task run_phase(uvm_phase phase);
    wb_can_burst_like_seq seq;
    phase.raise_objection(this);

    // First, put CAN in reset mode (required to write config registers)
    begin
      wb_can_single_access_seq rst_seq;
      rst_seq = wb_can_single_access_seq::type_id::create("rst_seq");
      wait(vif.rst == 0);
      `uvm_info("TEST", "Putting CAN in reset mode before burst writes", UVM_LOW)
      rst_seq.start(env.agt.sequencer);
    end

    // Store expected values
    exp_data[8'd6] = 8'h45;  // Bus Timing 0
    exp_data[8'd7] = 8'h23;  // Bus Timing 1
    exp_data[8'd4] = 8'hAB;  // Acceptance Code
    exp_data[8'd5] = 8'hFF;  // Acceptance Mask

    `uvm_info("TEST", "Starting WB-02 Consecutive Access Test (4 writes + 4 reads)", UVM_LOW)

    fork
      // Thread 1: Run the burst sequence
      begin
        seq = wb_can_burst_like_seq::type_id::create("seq");
        seq.start(env.agt.sequencer);
      end

      // Thread 2: Monitor ACK timing for all 8 burst transactions
      ack_monitor_thread(8);
    join

    // Report timing results
    report_timing();

    // Verify data integrity from scoreboard
    check_data_integrity();

    `uvm_info("TEST", "WB-02 Consecutive Access Test Complete", UVM_LOW)
    phase.drop_objection(this);
  endtask

  // Monitor ACK latency for each transaction
  task ack_monitor_thread(int num_transactions);
    for (int i = 0; i < num_transactions; i++) begin
      int count = 0;
      int max_wait = 20;
      string label;

      @(posedge vif.clk);
      wait(vif.stb && vif.cyc);
      label = vif.we ? "WRITE" : "READ";

      while (!vif.ack && count < max_wait) begin
        @(posedge vif.clk);
        count++;
      end

      ack_latencies.push_back(count);

      if (count >= max_wait) begin
        `uvm_error("ACK_TIMEOUT", $sformatf("[TXN-%0d %s] No ACK within %0d clocks", i, label, max_wait))
        timing_errors++;
      end else if (count >= 5 && count <= 10) begin
        `uvm_info("ACK_PASS", $sformatf("[TXN-%0d %s] ACK latency: %0d clocks OK", i, label, count), UVM_LOW)
      end else begin
        `uvm_error("ACK_FAIL", $sformatf("[TXN-%0d %s] ACK latency: %0d clocks (expected 5-10)", i, label, count))
        timing_errors++;
      end

      wait(!vif.stb);
    end
  endtask

  // Report timing summary
  function void report_timing();
    int min_lat = 999, max_lat = 0, sum = 0;

    foreach (ack_latencies[i]) begin
      if (ack_latencies[i] < min_lat) min_lat = ack_latencies[i];
      if (ack_latencies[i] > max_lat) max_lat = ack_latencies[i];
      sum += ack_latencies[i];
    end

    `uvm_info("TIMING_SUMMARY", $sformatf(
      "ACK Latency: min=%0d, max=%0d, avg=%0d clocks across %0d transactions | Timing Errors: %0d",
      min_lat, max_lat, sum / ack_latencies.size(), ack_latencies.size(), timing_errors), UVM_LOW)
  endfunction

  // Cross-check monitor-observed reads against expected values
  function void check_data_integrity();
    int pass_count = 0;
    int fail_count = 0;

    foreach (exp_data[addr]) begin
      if (env.scb.reg_map.exists(addr)) begin
        if (env.scb.reg_map[addr] == exp_data[addr]) begin
          `uvm_info("BURST_PASS", $sformatf("Addr=0x%0h: Written=0x%0h Stored=0x%0h MATCH",
                     addr, exp_data[addr], env.scb.reg_map[addr]), UVM_LOW)
          pass_count++;
        end else begin
          `uvm_error("BURST_FAIL", $sformatf("Addr=0x%0h: Expected=0x%0h Stored=0x%0h MISMATCH",
                      addr, exp_data[addr], env.scb.reg_map[addr]))
          fail_count++;
        end
      end else begin
        `uvm_error("BURST_FAIL", $sformatf("Addr=0x%0h: No write observed by scoreboard", addr))
        fail_count++;
      end
    end

    `uvm_info("BURST_SUMMARY", $sformatf("Data Integrity: %0d PASS, %0d FAIL out of %0d registers",
               pass_count, fail_count, pass_count + fail_count), UVM_LOW)
  endfunction
endclass
