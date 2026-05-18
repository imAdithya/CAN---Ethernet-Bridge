class wb_can_single_access_test extends uvm_test;
  `uvm_component_utils(wb_can_single_access_test)

  wb_can_env env;
  virtual wb_can_if vif;

  function new(string name = "wb_can_single_access_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = wb_can_env::type_id::create("env", this);
    
    if (!uvm_config_db#(virtual wb_can_if)::get(this, "", "vif", vif))
      `uvm_fatal("TEST", "Virtual interface not found in config_db")
  endfunction

  virtual task run_phase(uvm_phase phase);
    wb_can_single_access_seq seq;
    phase.raise_objection(this);

    // Synchronize with reset de-assertion
    wait(vif.rst == 0);
    `uvm_info("TEST", "Starting WB-01 Single Access Test", UVM_LOW)

    fork
      // Thread 1: Execute directed stimulus
      begin
        seq = wb_can_single_access_seq::type_id::create("seq");
        seq.start(env.agt.sequencer);
      end
      
      // Thread 2: Concurrent timing verification
      begin
        check_ack_timing("WRITE");
        check_ack_timing("READ");
      end
    join

    phase.drop_objection(this);
  endtask

  // Verifies that 'ack' asserts within a reasonable window after 'stb' and 'cyc'.
  // The SJA1000 CAN controller uses a clock-domain-crossing synchronization
  // scheme (cs_sync1 -> cs_sync2 -> cs_sync3 -> cs_ack1 -> cs_ack2 -> cs_ack3)
  // which produces an ACK approximately 7 wb_clk cycles after stb & cyc assert.
  task check_ack_timing(string label);
    int count = 0;
    int max_wait = 20; // Timeout safety

    @(posedge vif.clk);
    wait(vif.stb && vif.cyc);
    
    // Increment count on each clock edge until acknowledgment is received
    while (!vif.ack && count < max_wait) begin
      @(posedge vif.clk);
      count++;
    end

    if (count >= max_wait)
      `uvm_error("ACK_TIMEOUT", $sformatf("[%s] No ACK received within %0d clocks", label, max_wait))
    else if (count >= 5 && count <= 10)
      `uvm_info("ACK_PASS", $sformatf("[%s] Handshake timing OK: %0d clocks (expected ~7 for CDC sync)", label, count), UVM_LOW)
    else
      `uvm_error("ACK_FAIL", $sformatf("[%s] ACK latency unexpected: %0d clocks (expected 5-10 for CDC sync)", label, count))
    
    wait(!vif.stb);
  endtask
endclass
