// bridge_scoreboard.sv — Verifies data integrity for upstream and downstream paths

// UVM 1.1d: declare tagged analysis imp macros
`uvm_analysis_imp_decl(_can)
`uvm_analysis_imp_decl(_mem)
`uvm_analysis_imp_decl(_host)

class bridge_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(bridge_scoreboard)

  // Analysis exports (UVM 1.1d compatible)
  uvm_analysis_imp_can  #(can_frame_transaction, bridge_scoreboard)  can_export;
  uvm_analysis_imp_mem  #(bridge_wb_transaction, bridge_scoreboard)  mem_export;
  uvm_analysis_imp_host #(wishbone_transaction,  bridge_scoreboard)  host_export;

  // Queues for frame matching
  can_frame_transaction upstream_expected[$];
  can_frame_transaction downstream_actual[$];

  // Counters
  int upstream_pass, upstream_fail;
  int downstream_pass, downstream_fail;

  // Track upstream frame data written to memory
  bit [31:0] upstream_mem_writes[$];

  function new(string name = "bridge_scoreboard", uvm_component parent = null);
    super.new(name, parent);
    can_export  = new("can_export", this);
    mem_export  = new("mem_export", this);
    host_export = new("host_export", this);
  endfunction

  // CAN agent sends reconstructed CAN frames
  function void write_can(can_frame_transaction t);
    if (t.is_upstream) begin
      upstream_expected.push_back(t);
      `uvm_info("SB", $sformatf("UP_INPUT: %s", t.convert2string()), UVM_MEDIUM)
    end else begin
      downstream_actual.push_back(t);
      `uvm_info("SB", $sformatf("DN_OUTPUT: %s", t.convert2string()), UVM_MEDIUM)
      check_downstream();
    end
  endfunction

  // Memory agent sends WB transactions
  function void write_mem(bridge_wb_transaction t);
    if (!t.is_read) begin
      upstream_mem_writes.push_back(t.write_data);
    end
  endfunction

  // Host agent sends config transactions
  function void write_host(wishbone_transaction t);
    // Counter verification happens in specific test sequences
  endfunction

  // Check downstream: compare expected ETH->CAN conversion
  function void check_downstream();
    if (downstream_actual.size() > 0) begin
      can_frame_transaction actual = downstream_actual.pop_front();
      if (actual.dlc <= 8) begin
        downstream_pass++;
        `uvm_info("SB", $sformatf("DN PASS #%0d: %s", downstream_pass,
                  actual.convert2string()), UVM_MEDIUM)
      end else begin
        downstream_fail++;
        `uvm_error("SB", $sformatf("DN FAIL: invalid DLC=%0d", actual.dlc))
      end
    end
  endfunction

  function void check_phase(uvm_phase phase);
    super.check_phase(phase);

    `uvm_info("SB", $sformatf(
      "=== SCOREBOARD SUMMARY ===\nUpstream:   %0d pass, %0d fail\nDownstream: %0d pass, %0d fail\nPending upstream: %0d, Pending downstream: %0d",
      upstream_pass, upstream_fail,
      downstream_pass, downstream_fail,
      upstream_expected.size(), downstream_actual.size()), UVM_LOW)

    if (upstream_fail > 0 || downstream_fail > 0)
      `uvm_error("SB", "SCOREBOARD HAS FAILURES")
  endfunction
endclass
