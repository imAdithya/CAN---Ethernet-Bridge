// ============================================================
// CAN TX Functional Coverage Collector
// Subscribes to both Wishbone and CAN bus analysis ports
// to sample TX-specific covergroups.
// ============================================================

`uvm_analysis_imp_decl(_wb_cov)
`uvm_analysis_imp_decl(_can_cov)

class can_tx_coverage extends uvm_component;
  `uvm_component_utils(can_tx_coverage)

  // Analysis exports
  uvm_analysis_imp_wb_cov  #(wb_can_trans, can_tx_coverage) wb_export;
  uvm_analysis_imp_can_cov #(cb_trans_debug, can_tx_coverage) can_export;

  // Sampled fields from Wishbone (CMR commands, Status reads)
  logic [7:0] cmr_data;
  logic [7:0] status_data;
  bit         cmr_written;
  bit         status_read;

  // Sampled fields from CAN bus (decoded frames)
  bit         sampled_ide;
  bit         sampled_rtr;
  bit [28:0]  sampled_id;
  bit [3:0]   sampled_dlc;
  bit [7:0]   sampled_data[8];
  bit         frame_received;

  // Track frame statistics
  int total_sff_frames = 0;
  int total_eff_frames = 0;
  int total_data_frames = 0;
  int total_rtr_frames = 0;

  // ---------------------------------------------------------------
  // COVERGROUP 1: Frame Format (SFF vs EFF)
  // ---------------------------------------------------------------
  covergroup can_tx_frame_format_cg;
    option.per_instance = 1;
    cp_ff: coverpoint sampled_ide {
      bins SFF = {0};
      bins EFF = {1};
    }
  endgroup

  // ---------------------------------------------------------------
  // COVERGROUP 2: DLC Coverage (0-8)
  // ---------------------------------------------------------------
  covergroup can_tx_dlc_cg;
    option.per_instance = 1;
    cp_dlc: coverpoint sampled_dlc {
      bins dlc[] = {[0:8]};
    }
  endgroup

  // ---------------------------------------------------------------
  // COVERGROUP 3: RTR Coverage (Data vs Remote)
  // ---------------------------------------------------------------
  covergroup can_tx_rtr_cg;
    option.per_instance = 1;
    cp_rtr: coverpoint sampled_rtr {
      bins DATA   = {0};
      bins REMOTE = {1};
    }
  endgroup

  // ---------------------------------------------------------------
  // COVERGROUP 4: ID Range Coverage
  // ---------------------------------------------------------------
  covergroup can_tx_id_range_cg;
    option.per_instance = 1;

    // SFF ID ranges (11-bit)
    cp_sff_id: coverpoint sampled_id[10:0] iff (!sampled_ide) {
      bins zero      = {0};
      bins low       = {[1:511]};
      bins mid       = {[512:1535]};
      bins high      = {[1536:2046]};
      bins max       = {2047};
    }

    // EFF ID ranges (29-bit)
    cp_eff_id: coverpoint sampled_id iff (sampled_ide) {
      bins zero      = {0};
      bins low       = {[1:32'h1FFF]};
      bins mid       = {[32'h2000:32'h0FFFFFF]};
      bins high      = {[32'h1000000:32'h1FFFFFFE]};
      bins max       = {29'h1FFFFFFF};
    }
  endgroup

  // ---------------------------------------------------------------
  // COVERGROUP 5: CMR Command Coverage
  // ---------------------------------------------------------------
  covergroup can_tx_cmd_cg;
    option.per_instance = 1;
    cp_cmr: coverpoint cmr_data iff (cmr_written) {
      bins normal_tx     = {8'h01};  // CMR.0 = TX Request
      bins abort_tx      = {8'h02};  // CMR.1 = Abort
      bins single_shot   = {8'h03};  // CMR.0 + CMR.1 = Single Shot
      bins release_rx    = {8'h04};  // CMR.2 = Release RX Buffer
      bins self_rx       = {8'h10};  // CMR.4 = Self-Reception Request
      bins others        = default;
    }
  endgroup

  // ---------------------------------------------------------------
  // COVERGROUP 6: Data Byte Pattern Coverage
  // ---------------------------------------------------------------
  covergroup can_tx_data_pattern_cg;
    option.per_instance = 1;

    // Patterns seen in byte 0
    cp_byte0: coverpoint sampled_data[0] iff (!sampled_rtr && sampled_dlc > 0) {
      bins all_zero    = {8'h00};
      bins all_one     = {8'hFF};
      bins walking_1   = {8'h01, 8'h02, 8'h04, 8'h08, 8'h10, 8'h20, 8'h40, 8'h80};
      bins walking_0   = {8'hFE, 8'hFD, 8'hFB, 8'hF7, 8'hEF, 8'hDF, 8'hBF, 8'h7F};
      bins others      = default;
    }

    // Patterns seen across all 8 bytes
    cp_byte_any: coverpoint sampled_data[0] iff (!sampled_rtr && sampled_dlc > 0) {
      bins low_nibble  = {[8'h00:8'h0F]};
      bins mid_low     = {[8'h10:8'h7F]};
      bins mid_high    = {[8'h80:8'hEF]};
      bins high_nibble = {[8'hF0:8'hFF]};
    }
  endgroup

  // ---------------------------------------------------------------
  // COVERGROUP 7: Status Register Coverage
  // ---------------------------------------------------------------
  covergroup can_tx_status_cg;
    option.per_instance = 1;

    // TBS (Transmit Buffer Status) — bit 2
    cp_tbs: coverpoint status_data[2] iff (status_read) {
      bins buffer_locked   = {0};
      bins buffer_released = {1};
    }

    // TCS (Transmission Complete Status) — bit 3
    cp_tcs: coverpoint status_data[3] iff (status_read) {
      bins tx_incomplete = {0};
      bins tx_complete   = {1};
    }

    // TS (Transmit Status) — bit 5
    cp_ts: coverpoint status_data[5] iff (status_read) {
      bins idle         = {0};
      bins transmitting = {1};
    }
  endgroup

  // ---------------------------------------------------------------
  // COVERGROUP 8: CROSS — Frame Format x DLC
  // ---------------------------------------------------------------
  covergroup can_tx_format_x_dlc_cg;
    option.per_instance = 1;
    cp_ff:  coverpoint sampled_ide  { bins SFF = {0}; bins EFF = {1}; }
    cp_dlc: coverpoint sampled_dlc  { bins dlc[] = {[0:8]}; }
    ff_x_dlc: cross cp_ff, cp_dlc;
  endgroup

  // ---------------------------------------------------------------
  // COVERGROUP 9: CROSS — Frame Format x RTR
  // ---------------------------------------------------------------
  covergroup can_tx_format_x_rtr_cg;
    option.per_instance = 1;
    cp_ff:  coverpoint sampled_ide { bins SFF = {0}; bins EFF = {1}; }
    cp_rtr: coverpoint sampled_rtr { bins DATA = {0}; bins REMOTE = {1}; }
    ff_x_rtr: cross cp_ff, cp_rtr;
  endgroup

  // ---------------------------------------------------------------
  // Constructor
  // ---------------------------------------------------------------
  function new(string name, uvm_component parent);
    super.new(name, parent);
    wb_export  = new("wb_export", this);
    can_export = new("can_export", this);

    can_tx_frame_format_cg  = new();
    can_tx_dlc_cg           = new();
    can_tx_rtr_cg           = new();
    can_tx_id_range_cg      = new();
    can_tx_cmd_cg           = new();
    can_tx_data_pattern_cg  = new();
    can_tx_status_cg        = new();
    can_tx_format_x_dlc_cg  = new();
    can_tx_format_x_rtr_cg  = new();
  endfunction

  // ---------------------------------------------------------------
  // write_wb_cov() — Wishbone transactions (CMR commands, Status reads)
  // ---------------------------------------------------------------
  virtual function void write_wb_cov(wb_can_trans t);
    // Track CMR writes (Command Register at 0x01)
    if (t.we && t.addr == 8'h01) begin
      cmr_data = t.data;
      cmr_written = 1;
      can_tx_cmd_cg.sample();
      cmr_written = 0;
    end

    // Track Status Register reads (0x02)
    if (!t.we && t.addr == 8'h02) begin
      status_data = t.data;
      status_read = 1;
      can_tx_status_cg.sample();
      status_read = 0;
    end
  endfunction

  // ---------------------------------------------------------------
  // write_can_cov() — CAN bus observed frames
  // ---------------------------------------------------------------
  virtual function void write_can_cov(cb_trans_debug t);
    // Capture decoded frame fields
    sampled_ide  = t.ide;
    sampled_rtr  = t.rtr;
    sampled_id   = t.identifier;
    sampled_dlc  = t.dlc;
    for (int i = 0; i < 8; i++) sampled_data[i] = t.data[i];

    // Update statistics
    if (sampled_ide) total_eff_frames++; else total_sff_frames++;
    if (sampled_rtr) total_rtr_frames++; else total_data_frames++;

    // Sample all frame-level covergroups
    can_tx_frame_format_cg.sample();
    can_tx_dlc_cg.sample();
    can_tx_rtr_cg.sample();
    can_tx_id_range_cg.sample();
    can_tx_data_pattern_cg.sample();
    can_tx_format_x_dlc_cg.sample();
    can_tx_format_x_rtr_cg.sample();
  endfunction

  // ---------------------------------------------------------------
  // report_phase — Print TX Coverage Summary
  // ---------------------------------------------------------------
  virtual function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("TX_COV", "============================================", UVM_LOW)
    `uvm_info("TX_COV", "   CAN TX FUNCTIONAL COVERAGE SUMMARY", UVM_LOW)
    `uvm_info("TX_COV", "============================================", UVM_LOW)
    `uvm_info("TX_COV", $sformatf("  Total Frames: SFF=%0d EFF=%0d DATA=%0d RTR=%0d",
      total_sff_frames, total_eff_frames, total_data_frames, total_rtr_frames), UVM_LOW)
    `uvm_info("TX_COV", "--------------------------------------------", UVM_LOW)
    `uvm_info("TX_COV", $sformatf("  can_tx_frame_format_cg : %0.1f%%", can_tx_frame_format_cg.get_coverage()), UVM_LOW)
    `uvm_info("TX_COV", $sformatf("  can_tx_dlc_cg          : %0.1f%%", can_tx_dlc_cg.get_coverage()), UVM_LOW)
    `uvm_info("TX_COV", $sformatf("  can_tx_rtr_cg          : %0.1f%%", can_tx_rtr_cg.get_coverage()), UVM_LOW)
    `uvm_info("TX_COV", $sformatf("  can_tx_id_range_cg     : %0.1f%%", can_tx_id_range_cg.get_coverage()), UVM_LOW)
    `uvm_info("TX_COV", $sformatf("  can_tx_cmd_cg          : %0.1f%%", can_tx_cmd_cg.get_coverage()), UVM_LOW)
    `uvm_info("TX_COV", $sformatf("  can_tx_data_pattern_cg : %0.1f%%", can_tx_data_pattern_cg.get_coverage()), UVM_LOW)
    `uvm_info("TX_COV", $sformatf("  can_tx_status_cg       : %0.1f%%", can_tx_status_cg.get_coverage()), UVM_LOW)
    `uvm_info("TX_COV", $sformatf("  can_tx_format_x_dlc_cg : %0.1f%%", can_tx_format_x_dlc_cg.get_coverage()), UVM_LOW)
    `uvm_info("TX_COV", $sformatf("  can_tx_format_x_rtr_cg : %0.1f%%", can_tx_format_x_rtr_cg.get_coverage()), UVM_LOW)
    `uvm_info("TX_COV", "============================================", UVM_LOW)
  endfunction

endclass
