// ============================================================
// CAN Protocol Functional Coverage Collector
// Subscribes to Wishbone and CAN bus analysis ports
// ============================================================

`uvm_analysis_imp_decl(_prot_wb_cov)
`uvm_analysis_imp_decl(_prot_can_cov)

class can_prot_coverage extends uvm_component;
  `uvm_component_utils(can_prot_coverage)

  // Analysis exports
  uvm_analysis_imp_prot_wb_cov  #(wb_can_trans, can_prot_coverage) wb_export;
  uvm_analysis_imp_prot_can_cov #(cb_trans_debug, can_prot_coverage) can_export;

  logic [7:0] alc_data;
  bit         alc_read = 0;

  bit         sampled_ide;
  bit [28:0]  sampled_id;
  bit [7:0]   sampled_data[8];
  bit [3:0]   sampled_dlc;

  // ---------------------------------------------------------------
  // COVERGROUP 1: Arbitration (can_arb_std_test, can_arb_ext_test)
  // ---------------------------------------------------------------
  covergroup can_prot_arb_cg;
    option.per_instance = 1;
    cp_ide: coverpoint sampled_ide {
      bins sff_arb = {0};
      bins eff_arb = {1};
    }
  endgroup

  // ---------------------------------------------------------------
  // COVERGROUP 2: ALC Capture (can_alc_capture_test)
  // ---------------------------------------------------------------
  covergroup can_prot_alc_cg;
    option.per_instance = 1;
    // ALC register captures arbitration lost location (bits 4:0)
    cp_alc: coverpoint alc_data[4:0] iff (alc_read) {
      bins id28_to_id21 = {[0:7]};
      bins id20_to_id13 = {[8:15]};
      bins others       = {[16:31]};
    }
  endgroup

  // ---------------------------------------------------------------
  // COVERGROUP 3: Bit Stuffing (can_bit_stuff_test)
  // ---------------------------------------------------------------
  covergroup can_prot_bit_stuff_cg;
    option.per_instance = 1;
    // Specific data patterns intended to force bit stuffing
    cp_stuff_data: coverpoint sampled_data[0] iff (sampled_dlc > 0) {
      bins all_zeros = {8'h00};
      bins all_ones  = {8'hFF};
      bins alt_55    = {8'h55};
      bins alt_AA    = {8'hAA};
    }
  endgroup

  // Constructor
  function new(string name, uvm_component parent);
    super.new(name, parent);
    wb_export  = new("wb_export", this);
    can_export = new("can_export", this);

    can_prot_arb_cg = new();
    can_prot_alc_cg = new();
    can_prot_bit_stuff_cg = new();
  endfunction

  virtual function void write_prot_wb_cov(wb_can_trans t);
    // ALC Register Read
    if (!t.we && t.addr == 8'h0B) begin
      alc_data = t.data;
      alc_read = 1;
      can_prot_alc_cg.sample();
      alc_read = 0;
    end
  endfunction

  virtual function void write_prot_can_cov(cb_trans_debug t);
    sampled_ide = t.ide;
    sampled_id  = t.identifier;
    sampled_dlc = t.dlc;
    for (int i = 0; i < 8; i++) sampled_data[i] = t.data[i];

    can_prot_arb_cg.sample();
    can_prot_bit_stuff_cg.sample();
  endfunction

endclass
