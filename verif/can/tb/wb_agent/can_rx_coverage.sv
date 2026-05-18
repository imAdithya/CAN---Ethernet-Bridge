// ============================================================
// CAN RX Functional Coverage Collector
// Subscribes to Wishbone and CAN bus analysis ports
// ============================================================

`uvm_analysis_imp_decl(_rx_wb_cov)
`uvm_analysis_imp_decl(_rx_can_cov)

class can_rx_coverage extends uvm_component;
  `uvm_component_utils(can_rx_coverage)

  // Analysis exports
  uvm_analysis_imp_rx_wb_cov  #(wb_can_trans, can_rx_coverage) wb_export;
  uvm_analysis_imp_rx_can_cov #(cb_trans_debug, can_rx_coverage) can_export;

  // Sampled fields
  logic [7:0] mode_reg = 8'h01;
  logic [7:0] cmr_data;
  logic [7:0] status_data;
  logic [7:0] rmc_data;
  bit         cmr_written = 0;
  bit         status_read = 0;
  bit         rmc_read = 0;

  bit         sampled_ide;
  bit         sampled_rtr;
  bit [28:0]  sampled_id;
  bit [3:0]   sampled_dlc;

  // ---------------------------------------------------------------
  // COVERGROUP 1: Single/Dual Filter Match (can_rx_single_filter_test, can_rx_dual_filter_test)
  // ---------------------------------------------------------------
  covergroup can_rx_filter_mode_cg;
    option.per_instance = 1;
    // Mode register bit 3 (AFM: Acceptance Filter Mode)
    // 0 = Dual Filter Mode, 1 = Single Filter Mode
    cp_afm: coverpoint mode_reg[3] {
      bins dual_filter   = {0};
      bins single_filter = {1};
    }
  endgroup

  // ---------------------------------------------------------------
  // COVERGROUP 2: Overrun Status (can_rx_overrun_test)
  // ---------------------------------------------------------------
  covergroup can_rx_overrun_cg;
    option.per_instance = 1;
    // Status Register bit 1 (DOS: Data Overrun Status)
    cp_dos: coverpoint status_data[1] iff (status_read) {
      bins no_overrun = {0};
      bins overrun    = {1};
    }
  endgroup

  // ---------------------------------------------------------------
  // COVERGROUP 3: RX Message Counter (can_rx_rmc_test)
  // ---------------------------------------------------------------
  covergroup can_rx_rmc_cg;
    option.per_instance = 1;
    // RMC values 0 to 64
    cp_rmc: coverpoint rmc_data iff (rmc_read) {
      bins empty     = {0};
      bins low_count = {[1:10]};
      bins mid_count = {[11:15]};
      bins max_count = {[16:31]}; // SJA1000 max capacity is 21 messages
    }
  endgroup

  // ---------------------------------------------------------------
  // COVERGROUP 4: RX Buffer Release (can_rx_release_test)
  // ---------------------------------------------------------------
  covergroup can_rx_release_cg;
    option.per_instance = 1;
    // Command Register bit 2 (RRB: Release Receive Buffer)
    cp_rrb: coverpoint cmr_data[2] iff (cmr_written) {
      bins do_release = {1};
    }
  endgroup

  // ---------------------------------------------------------------
  // COVERGROUP 5: RTR Frame Handling (can_rx_rtr_test)
  // ---------------------------------------------------------------
  covergroup can_rx_rtr_cg;
    option.per_instance = 1;
    cp_rtr: coverpoint sampled_rtr {
      bins data_frame   = {0};
      bins remote_frame = {1};
    }
  endgroup

  // ---------------------------------------------------------------
  // COVERGROUP 6: Data Integrity / Formats (can_rx_integrity_test)
  // ---------------------------------------------------------------
  covergroup can_rx_format_cg;
    option.per_instance = 1;
    cp_ide: coverpoint sampled_ide {
      bins sff = {0};
      bins eff = {1};
    }
    cp_dlc: coverpoint sampled_dlc {
      bins empty   = {0};
      bins partial = {[1:7]};
      bins full    = {8};
    }
    cross cp_ide, cp_dlc;
  endgroup

  // Constructor
  function new(string name, uvm_component parent);
    super.new(name, parent);
    wb_export  = new("wb_export", this);
    can_export = new("can_export", this);

    can_rx_filter_mode_cg = new();
    can_rx_overrun_cg = new();
    can_rx_rmc_cg = new();
    can_rx_release_cg = new();
    can_rx_rtr_cg = new();
    can_rx_format_cg = new();
  endfunction

  virtual function void write_rx_wb_cov(wb_can_trans t);
    // Mode Register
    if (t.we && t.addr == 8'h00) begin
      mode_reg = t.data;
      can_rx_filter_mode_cg.sample();
    end

    // Command Register (CMR)
    if (t.we && t.addr == 8'h01) begin
      cmr_data = t.data;
      cmr_written = 1;
      can_rx_release_cg.sample();
      cmr_written = 0;
    end

    // Status Register
    if (!t.we && t.addr == 8'h02) begin
      status_data = t.data;
      status_read = 1;
      can_rx_overrun_cg.sample();
      status_read = 0;
    end

    // RMC Register
    if (!t.we && t.addr == 8'h1D) begin
      rmc_data = t.data;
      rmc_read = 1;
      can_rx_rmc_cg.sample();
      rmc_read = 0;
    end
  endfunction

  virtual function void write_rx_can_cov(cb_trans_debug t);
    // Note: Assuming we cover what the bus transmits and eventually the RX receives.
    sampled_ide = t.ide;
    sampled_rtr = t.rtr;
    sampled_id  = t.identifier;
    sampled_dlc = t.dlc;

    can_rx_rtr_cg.sample();
    can_rx_format_cg.sample();
  endfunction

endclass
