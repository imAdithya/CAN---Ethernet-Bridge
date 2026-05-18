class wb_can_coverage extends uvm_subscriber #(wb_can_trans);
  `uvm_component_utils(wb_can_coverage)

  // Transaction fields for sampling
  logic [7:0] sampled_addr;
  logic [7:0] sampled_data;
  logic       sampled_we;

  // Track back-to-back transactions
  time last_txn_time = 0;
  bit  is_b2b = 0;

  // Track mode register state for mode-aware coverpoints
  logic [7:0] last_mode_data = 8'h01;  // Default: reset mode
  bit         in_reset_mode  = 1;

  // Track reset events
  bit reset_seen = 0;
  int post_reset_txn_count = 0;

  // ---------------------------------------------------------------
  // COVERGROUP 1: Wishbone Transaction Coverage (WB-01 Single Access)
  // Sampled on every completed WB transaction (stb && cyc && ack)
  // Verifies: basic read/write to all address ranges
  // ---------------------------------------------------------------
  covergroup wb_can_cg;
    option.per_instance = 1;

    // Which SJA1000 register address ranges were accessed?
    cp_addr: coverpoint sampled_addr {
      bins mode_reg    = {8'h00};               // Mode register
      bins cmd_status  = {[8'h01 : 8'h03]};     // Command, Status, Interrupt
      bins config_regs = {[8'h04 : 8'h07]};     // Bus Timing, Output Control
      bins tx_regs     = {[8'h08 : 8'h0F]};     // TX buffer
      bins rx_regs     = {[8'h10 : 8'h17]};     // RX buffer / Acceptance
      bins upper_regs  = {[8'h18 : 8'h1F]};     // Error counters, misc
    }

    // Read vs Write
    cp_we: coverpoint sampled_we {
      bins READ  = {1'b0};
      bins WRITE = {1'b1};
    }

    // Data value patterns
    cp_data: coverpoint sampled_data {
      bins zero      = {8'h00};
      bins all_ones  = {8'hFF};
      bins low_range = {[8'h01 : 8'h7F]};
      bins high_range= {[8'h80 : 8'hFE]};
    }

    // CROSS: Did we both READ and WRITE to every address range?
    addr_x_we: cross cp_addr, cp_we;

  endgroup

  // ---------------------------------------------------------------
  // COVERGROUP 2: Bus Timing / Protocol Coverage (WB-02 Burst-Like)
  // Verifies: back-to-back transactions with no idle gaps
  // ---------------------------------------------------------------
  covergroup wb_can_timing_cg;
    option.per_instance = 1;

    // Were there back-to-back transactions (no idle gap)?
    cp_b2b: coverpoint is_b2b {
      bins idle_gap     = {1'b0};
      bins back_to_back = {1'b1};
    }
  endgroup

  // ---------------------------------------------------------------
  // COVERGROUP 3: Register Access Coverage (WB-04 Reg Access)
  // Verifies: every individual register address was both read & written
  // ---------------------------------------------------------------
  covergroup wb_reg_access_cg;
    option.per_instance = 1;

    // Every individual address in the SJA1000 register map
    cp_full_addr: coverpoint sampled_addr {
      bins addr[] = {[8'h00 : 8'h1F]};
      ignore_bins unused = {8'h1E}; // 30 is reserved/unused
    }

    // Cross with R/W direction
    cp_we: coverpoint sampled_we {
      bins READ  = {1'b0};
      bins WRITE = {1'b1};
    }

    full_addr_x_we: cross cp_full_addr, cp_we {
      // Write-Only registers (cannot be read)
      ignore_bins write_only = binsof(cp_full_addr) intersect {8'h01, 8'h08, 8'h09, 8'h0A} && binsof(cp_we) intersect {1'b0};
      
      // Registers not accessible in our tests (ALC, ECC, RMC, ERX, ETX are tested in CAN agent, not WB agent)
      ignore_bins no_wb_access = binsof(cp_full_addr) intersect {[8'h18 : 8'h1C]} && binsof(cp_we);
    }
  endgroup

  // ---------------------------------------------------------------
  // COVERGROUP 4: Register Reset Values (WB-05 Reg Reset)
  // Verifies: reset-value readback from key registers
  // ---------------------------------------------------------------
  covergroup wb_reg_reset_cg;
    option.per_instance = 1;

    // Key registers read after reset (addr during read ops)
    cp_reset_read_addr: coverpoint sampled_addr iff (!sampled_we) {
      bins mode_reg    = {8'h00};   // MOD — expected reset val
      bins status_reg  = {8'h02};   // SR
      bins irq_reg     = {8'h03};   // IR
      bins btr0_reg    = {8'h06};   // BTR0
      bins btr1_reg    = {8'h07};   // BTR1
      bins err_warn    = {8'h0D};   // EWLR
      bins rx_err_cnt  = {8'h0E};   // RXERR
      bins tx_err_cnt  = {8'h0F};   // TXERR
      bins cdr_reg     = {8'h1F};   // CDR
    }

    // Common reset data values read back
    cp_reset_data: coverpoint sampled_data iff (!sampled_we) {
      bins val_00 = {8'h00};
      bins val_01 = {8'h01};
      bins val_BC = {8'hBC};  // Status reg reset value in RTL (Bus-Off locked)
      bins others = default;
    }
  endgroup

  // ---------------------------------------------------------------
  // COVERGROUP 5: Read-Only Register Protection (WB-06 Reg RO)
  // Verifies: writes attempted to read-only registers
  // ---------------------------------------------------------------
  covergroup wb_reg_ro_cg;
    option.per_instance = 1;

    // Write attempts to known read-only registers
    cp_ro_write: coverpoint sampled_addr iff (sampled_we) {
      bins status_reg     = {8'h02};   // SR  (read-only)
      bins irq_reg        = {8'h03};   // IR  (read-only / read-clear)
      bins arb_lost_cap   = {8'h0B};   // ALC (read-only in PeliCAN)
      bins err_code_cap   = {8'h0C};   // ECC (read-only in PeliCAN)
      bins rx_msg_cnt     = {8'h1D};   // RMC (read-only)
    }

    // Read-back after write attempt (verifying value unchanged)
    cp_ro_read: coverpoint sampled_addr iff (!sampled_we) {
      bins status_reg     = {8'h02};
      bins irq_reg        = {8'h03};
      bins arb_lost_cap   = {8'h0B};
      bins err_code_cap   = {8'h0C};
      bins rx_msg_cnt     = {8'h1D};
    }
  endgroup

  // ---------------------------------------------------------------
  // COVERGROUP 6: Reset Mode Register Locking (WB-07 Reset Mode Lock)
  // Verifies: config registers reject writes in operating mode
  // ---------------------------------------------------------------
  covergroup wb_reset_mode_lock_cg;
    option.per_instance = 1;

    // Writes to config registers that should be locked in operating mode
    cp_locked_reg_write: coverpoint sampled_addr iff (sampled_we && !in_reset_mode) {
      bins btr0_locked = {8'h06};   // BTR0 — locked in operating mode
      bins btr1_locked = {8'h07};   // BTR1 — locked in operating mode
      bins acr_locked  = {8'h10};   // ACR0 — locked in operating mode (PeliCAN)
      bins amr_locked  = {8'h14};   // AMR0 — locked in operating mode (PeliCAN)
    }

    // Writes to config registers in reset mode (should succeed)
    cp_config_reg_write: coverpoint sampled_addr iff (sampled_we && in_reset_mode) {
      bins btr0_unlocked = {8'h06};
      bins btr1_unlocked = {8'h07};
      bins acr_unlocked  = {8'h10};
      bins amr_unlocked  = {8'h14};
    }

    // Mode register writes (entering/exiting reset mode)
    cp_mode_write: coverpoint sampled_data iff (sampled_we && sampled_addr == 8'h00) {
      bins enter_reset    = {8'h01};
      bins exit_reset     = {8'h00};
    }
  endgroup

  // ---------------------------------------------------------------
  // COVERGROUP 7: Mode Switching (WB-08 Mode Switch)
  // Verifies: BasicCAN <-> PeliCAN mode transitions via CDR.7
  // ---------------------------------------------------------------
  covergroup wb_mode_switch_cg;
    option.per_instance = 1;

    // CDR register writes (addr=0x1F) — bit 7 controls mode
    cp_cdr_mode_bit: coverpoint sampled_data[7] iff (sampled_we && sampled_addr == 8'h1F) {
      bins basic_can  = {1'b0};   // CDR.7=0 → BasicCAN mode
      bins pelican    = {1'b1};   // CDR.7=1 → PeliCAN mode
    }

    // Mode register value when switching modes
    cp_mode_during_switch: coverpoint sampled_data iff (sampled_we && sampled_addr == 8'h00) {
      bins reset_mode   = {8'h01};   // Must be in reset mode to switch
      bins operating    = {8'h00};   // Re-enter operating after switch
    }
  endgroup

  // ---------------------------------------------------------------
  // COVERGROUP 8: Clock Divider Ratios (WB-10 Clk Div)
  // Verifies: all 8 CDR[2:0] divider values were programmed
  // ---------------------------------------------------------------
  covergroup wb_clk_div_cg;
    option.per_instance = 1;

    // All 8 clock divider ratio values written to CDR
    cp_cdr_div_value: coverpoint sampled_data[2:0] iff (sampled_we && sampled_addr == 8'h1F) {
      bins div_2   = {3'b000};   // f_clkout = f_osc / 2
      bins div_4   = {3'b001};   // f_clkout = f_osc / 4
      bins div_6   = {3'b010};   // f_clkout = f_osc / 6
      bins div_8   = {3'b011};   // f_clkout = f_osc / 8
      bins div_10  = {3'b100};   // f_clkout = f_osc / 10
      bins div_12  = {3'b101};   // f_clkout = f_osc / 12
      bins div_14  = {3'b110};   // f_clkout = f_osc / 14
      bins div_1   = {3'b111};   // f_clkout = f_osc (bypass)
    }
  endgroup

  // ---------------------------------------------------------------
  // COVERGROUP 9: Reset Stress / Recovery (WB-03 Reset Stress)
  // Verifies: bus transactions work after reset recovery
  // ---------------------------------------------------------------
  covergroup wb_reset_recovery_cg;
    option.per_instance = 1;

    // Post-reset transaction direction
    cp_post_reset_we: coverpoint sampled_we iff (reset_seen) {
      bins post_reset_read  = {1'b0};
      bins post_reset_write = {1'b1};
    }

    // Post-reset transaction addresses (verifying bus is functional)
    cp_post_reset_addr: coverpoint sampled_addr iff (reset_seen) {
      bins mode_reg   = {8'h00};
      bins other_regs = default;
    }
  endgroup

  // ---------------------------------------------------------------
  // Constructor
  // ---------------------------------------------------------------
  function new(string name, uvm_component parent);
    super.new(name, parent);
    wb_can_cg            = new();
    wb_can_timing_cg     = new();
    wb_reg_access_cg     = new();
    wb_reg_reset_cg      = new();
    wb_reg_ro_cg         = new();
    wb_reset_mode_lock_cg = new();
    wb_mode_switch_cg    = new();
    wb_clk_div_cg        = new();
    wb_reset_recovery_cg = new();
  endfunction

  // ---------------------------------------------------------------
  // write() — called by the monitor's analysis port on every txn
  // ---------------------------------------------------------------
  virtual function void write(wb_can_trans t);
    // Capture fields for sampling
    sampled_addr = t.addr;
    sampled_data = t.data;
    sampled_we   = t.we;

    // Track mode register state
    if (sampled_addr == 8'h00 && sampled_we) begin
      last_mode_data = sampled_data;
      in_reset_mode  = sampled_data[0];  // MOD.0 = Reset Mode
    end

    // Track reset recovery (detect transitions into reset mode)
    if (sampled_addr == 8'h00 && sampled_we && sampled_data[0]) begin
      reset_seen = 1;
      post_reset_txn_count = 0;
    end
    if (reset_seen)
      post_reset_txn_count++;

    // Detect back-to-back: if current time is within 14 clock cycles of last txn
    if (last_txn_time != 0) begin
      time delta = $time - last_txn_time;
      `uvm_info("COV_TIMING", $sformatf("Time since last txn: %0t", delta), UVM_HIGH)
      
      if (delta <= 560ns)
        is_b2b = 1;
      else
        is_b2b = 0;
    end else begin
      is_b2b = 0;
    end
    last_txn_time = $time;

    // Sample all covergroups
    wb_can_cg.sample();
    wb_can_timing_cg.sample();
    wb_reg_access_cg.sample();
    wb_reg_reset_cg.sample();
    wb_reg_ro_cg.sample();
    wb_reset_mode_lock_cg.sample();
    wb_mode_switch_cg.sample();
    wb_clk_div_cg.sample();
    wb_reset_recovery_cg.sample();

    `uvm_info("COV", $sformatf("Sampled: addr=0x%0h data=0x%0h we=%0b b2b=%0b mode=%s",
              sampled_addr, sampled_data, sampled_we, is_b2b,
              in_reset_mode ? "RESET" : "OPER"), UVM_HIGH)
  endfunction

  // ---------------------------------------------------------------
  // report_phase — print final coverage summary
  // ---------------------------------------------------------------
  virtual function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("COV_REPORT", "============================================", UVM_LOW)
    `uvm_info("COV_REPORT", "   FUNCTIONAL COVERAGE SUMMARY", UVM_LOW)
    `uvm_info("COV_REPORT", "============================================", UVM_LOW)
    `uvm_info("COV_REPORT", $sformatf("  wb_can_cg            : %0.1f%%", wb_can_cg.get_coverage()), UVM_LOW)
    `uvm_info("COV_REPORT", $sformatf("  wb_can_timing_cg     : %0.1f%%", wb_can_timing_cg.get_coverage()), UVM_LOW)
    `uvm_info("COV_REPORT", $sformatf("  wb_reg_access_cg     : %0.1f%%", wb_reg_access_cg.get_coverage()), UVM_LOW)
    `uvm_info("COV_REPORT", $sformatf("  wb_reg_reset_cg      : %0.1f%%", wb_reg_reset_cg.get_coverage()), UVM_LOW)
    `uvm_info("COV_REPORT", $sformatf("  wb_reg_ro_cg         : %0.1f%%", wb_reg_ro_cg.get_coverage()), UVM_LOW)
    `uvm_info("COV_REPORT", $sformatf("  wb_reset_mode_lock_cg: %0.1f%%", wb_reset_mode_lock_cg.get_coverage()), UVM_LOW)
    `uvm_info("COV_REPORT", $sformatf("  wb_mode_switch_cg    : %0.1f%%", wb_mode_switch_cg.get_coverage()), UVM_LOW)
    `uvm_info("COV_REPORT", $sformatf("  wb_clk_div_cg        : %0.1f%%", wb_clk_div_cg.get_coverage()), UVM_LOW)
    `uvm_info("COV_REPORT", $sformatf("  wb_reset_recovery_cg : %0.1f%%", wb_reset_recovery_cg.get_coverage()), UVM_LOW)
    `uvm_info("COV_REPORT", "============================================", UVM_LOW)
  endfunction

endclass
