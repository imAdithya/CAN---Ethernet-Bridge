// ============================================================
// CAN Error Management Coverage Collector
// Subscribes to Wishbone analysis port
// ============================================================

`uvm_analysis_imp_decl(_err_wb_cov)

class can_err_coverage extends uvm_component;
  `uvm_component_utils(can_err_coverage)

  // Analysis exports
  uvm_analysis_imp_err_wb_cov #(wb_can_trans, can_err_coverage) wb_export;

  logic [7:0] status_data;
  logic [7:0] ecc_data;
  logic [7:0] txerr_data;
  logic [7:0] rxerr_data;

  bit status_read = 0;
  bit ecc_read = 0;
  bit txerr_read = 0;
  bit rxerr_read = 0;

  // ---------------------------------------------------------------
  // COVERGROUP 1: Error Code Capture (can_ecc_capture_test and specific error tests)
  // ---------------------------------------------------------------
  covergroup can_err_ecc_cg;
    option.per_instance = 1;
    // ECC bits [7:6] Error Code
    cp_err_code: coverpoint ecc_data[7:6] iff (ecc_read) {
      bins bit_error   = {2'b00};
      bins form_error  = {2'b01};
      bins stuff_error = {2'b10};
      bins other_error = {2'b11};
    }
  endgroup

  // ---------------------------------------------------------------
  // COVERGROUP 2: Status Register Transitions (can_state_transition_test, can_err_cnt_warning_test)
  // ---------------------------------------------------------------
  covergroup can_err_status_cg;
    option.per_instance = 1;
    // SR.6 Error Status (Warning limit crossed)
    cp_error_status: coverpoint status_data[6] iff (status_read) {
      bins ok      = {0};
      bins warning = {1};
    }
    // SR.7 Bus Status (Bus Off)
    cp_bus_status: coverpoint status_data[7] iff (status_read) {
      bins bus_on  = {0};
      bins bus_off = {1};
    }
    cross cp_error_status, cp_bus_status {
      ignore_bins illegal_warning_bus_off = binsof(cp_error_status.warning) && binsof(cp_bus_status.bus_off);
    }
  endgroup

  // ---------------------------------------------------------------
  // COVERGROUP 3: TX/RX Error Counters (can_err_cnt_warning_test, can_state_transition_test)
  // ---------------------------------------------------------------
  covergroup can_err_counters_cg;
    option.per_instance = 1;
    cp_txerr: coverpoint txerr_data iff (txerr_read) {
      bins low     = {[0:95]};
      bins warning = {[96:127]};
      bins passive = {[128:255]};
    }
    cp_rxerr: coverpoint rxerr_data iff (rxerr_read) {
      bins low     = {[0:95]};
      bins warning = {[96:127]};
      bins passive = {[128:254]};
    }
  endgroup

  // Constructor
  function new(string name, uvm_component parent);
    super.new(name, parent);
    wb_export = new("wb_export", this);

    can_err_ecc_cg      = new();
    can_err_status_cg   = new();
    can_err_counters_cg = new();
  endfunction

  virtual function void write_err_wb_cov(wb_can_trans t);
    // Status Register
    if (!t.we && t.addr == 8'h02) begin
      status_data = t.data;
      status_read = 1;
      can_err_status_cg.sample();
      status_read = 0;
    end

    // ECC Register
    if (!t.we && t.addr == 8'h0C) begin
      ecc_data = t.data;
      ecc_read = 1;
      can_err_ecc_cg.sample();
      ecc_read = 0;
    end

    // TXERR Register
    if (!t.we && t.addr == 8'h0F) begin
      txerr_data = t.data;
      txerr_read = 1;
      can_err_counters_cg.sample();
      txerr_read = 0;
    end

    // RXERR Register
    if (!t.we && t.addr == 8'h0E) begin
      rxerr_data = t.data;
      rxerr_read = 1;
      can_err_counters_cg.sample();
      rxerr_read = 0;
    end
  endfunction

endclass
