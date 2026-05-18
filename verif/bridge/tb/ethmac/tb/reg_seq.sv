// tb/sequences/reg_seq.sv — Register sequences using raw Wishbone access
`include "uvm_macros.svh"
import uvm_pkg::*;
`include "ethmac_defines.v"

// =========================================================================
// Register Address Constants (shared across all reg sequences)
// =========================================================================
// RW registers (safe to write)
localparam int NUM_RW_REGS = 19;
localparam logic [31:0] RW_REG_ADDRS [NUM_RW_REGS] = '{
  32'h00, 32'h08, 32'h0C, 32'h10, 32'h14, 32'h18, 32'h1C,
  32'h20, 32'h24, 32'h28, 32'h2C, 32'h30, 32'h34,
  32'h40, 32'h44, 32'h48, 32'h4C, 32'h50, 32'h54
};
localparam string RW_REG_NAMES [NUM_RW_REGS] = '{
  "MODER", "INT_MASK", "IPGT", "IPGR1", "IPGR2", "PACKETLEN", "COLLCONF",
  "TX_BD_NUM", "CTRLMODER", "MIIMODER", "MIICOMMAND", "MIIADDRESS", "MIITX_DATA",
  "MAC_ADDR0", "MAC_ADDR1", "HASH0", "HASH1", "TX_CTRL", "RX_CTRL"
};

// RO registers
localparam int NUM_RO_REGS = 3;
localparam logic [31:0] RO_REG_ADDRS [NUM_RO_REGS] = '{32'h04, 32'h38, 32'h3C};
localparam string RO_REG_NAMES [NUM_RO_REGS] = '{"INT_SOURCE", "MIIRX_DATA", "MIISTATUS"};

// All registers (RW + RO)
localparam int NUM_ALL_REGS = NUM_RW_REGS + NUM_RO_REGS;

// Known reset values for all registers (RW then RO order)
localparam logic [31:0] REG_RESET_VALS [NUM_ALL_REGS] = '{
  // RW: MODER, INT_MASK, IPGT, IPGR1, IPGR2, PACKETLEN, COLLCONF,
  32'h0000_A000, 32'h0, 32'h0, 32'h0, 32'h0, 32'h00400600, 32'h000F003F,
  // RW: TX_BD_NUM, CTRLMODER, MIIMODER, MIICOMMAND, MIIADDRESS, MIITX_DATA,
  32'h40, 32'h0, 32'h0064, 32'h0, 32'h0, 32'h0,
  // RW: MAC_ADDR0, MAC_ADDR1, HASH0, HASH1, TX_CTRL, RX_CTRL
  32'h0, 32'h0, 32'h0, 32'h0, 32'h0, 32'h0,
  // RO: INT_SOURCE, MIIRX_DATA, MIISTATUS
  32'h0, 32'h0, 32'h0
};

// =========================================================================
// Random Register Access — write random values, readback
// =========================================================================
class random_reg_access_seq extends uvm_sequence #(wishbone_transaction);
  `uvm_object_utils(random_reg_access_seq)

  reg_write_seq write_seq;
  reg_read_seq  read_seq;

  rand int unsigned num_transactions;
  constraint c_num_transactions { num_transactions inside {[20:50]}; }

  function new(string name = "random_reg_access_seq");
    super.new(name);
  endfunction

  virtual task body();
    logic [31:0] wdata, rdata;
    int unsigned rand_index;

    write_seq = reg_write_seq::type_id::create("write_seq");
    read_seq  = reg_read_seq::type_id::create("read_seq");

    `uvm_info(get_type_name(), "Starting Random Register Access Test...", UVM_MEDIUM)

    repeat(num_transactions) begin
      // Pick a random register from ALL registers
      if (!std::randomize(rand_index) with { rand_index < NUM_ALL_REGS; })
        `uvm_fatal("SEQ", "Randomization failed")

      if (rand_index >= NUM_RW_REGS) begin
        // RO register — just read it
        int ro_idx = rand_index - NUM_RW_REGS;
        read_seq.addr = RO_REG_ADDRS[ro_idx];
        read_seq.start(m_sequencer);
        rdata = read_seq.data;
        `uvm_info("SEQ", $sformatf("READ %s (0x%02h) = 0x%0h", RO_REG_NAMES[ro_idx], RO_REG_ADDRS[ro_idx], rdata), UVM_HIGH)
      end else begin
        // RW register — write random, then read back
        if (!std::randomize(wdata))
          `uvm_error("SEQ", "Rand failed")

        // Special case: TX_BD_NUM must be 1-128
        if (RW_REG_ADDRS[rand_index] == 32'h20) begin
          wdata = wdata & 32'h7F;
          if (wdata == 0) wdata = 1;
        end

        write_seq.addr = RW_REG_ADDRS[rand_index];
        write_seq.data = wdata;
        write_seq.start(m_sequencer);

        read_seq.addr = RW_REG_ADDRS[rand_index];
        read_seq.start(m_sequencer);
        rdata = read_seq.data;

        `uvm_info("SEQ", $sformatf("W/R %s (0x%02h): wrote=0x%0h read=0x%0h",
                  RW_REG_NAMES[rand_index], RW_REG_ADDRS[rand_index], wdata, rdata), UVM_HIGH)
      end
    end

    `uvm_info(get_type_name(), "Test Finished.", UVM_MEDIUM)
  endtask
endclass

// =========================================================================
// Register Reset Check — read all registers and verify reset values
// =========================================================================
class reg_reset_seq extends uvm_sequence #(wishbone_transaction);
  `uvm_object_utils(reg_reset_seq)

  reg_read_seq read_seq;

  function new(string name = "reg_reset_seq");
    super.new(name);
  endfunction

  virtual task body();
    logic [31:0] rdata;
    int reg_idx;

    read_seq = reg_read_seq::type_id::create("read_seq");

    `uvm_info(get_type_name(),
              "Starting register reset value check...",
              UVM_MEDIUM)

    reg_idx = 0;

    // Check RW registers
    for (int i = 0; i < NUM_RW_REGS; i++) begin
      read_seq.addr = RW_REG_ADDRS[i];
      read_seq.start(m_sequencer);
      rdata = read_seq.data;
      `uvm_info("SEQ", $sformatf("Reset check: %s (0x%02h) = 0x%0h (expected 0x%0h)",
                RW_REG_NAMES[i], RW_REG_ADDRS[i], rdata, REG_RESET_VALS[reg_idx]), UVM_HIGH)
      reg_idx++;
    end

    // Check RO registers
    for (int i = 0; i < NUM_RO_REGS; i++) begin
      read_seq.addr = RO_REG_ADDRS[i];
      read_seq.start(m_sequencer);
      rdata = read_seq.data;
      `uvm_info("SEQ", $sformatf("Reset check: %s (0x%02h) = 0x%0h (expected 0x%0h)",
                RO_REG_NAMES[i], RO_REG_ADDRS[i], rdata, REG_RESET_VALS[reg_idx]), UVM_HIGH)
      reg_idx++;
    end

    `uvm_info(get_type_name(),
              "Register reset value check finished.",
              UVM_MEDIUM)
  endtask
endclass

// =========================================================================
// Read-Only Access Test — attempt writes to RO registers, verify unchanged
// =========================================================================
class reg_ro_access_seq extends uvm_sequence #(wishbone_transaction);
  `uvm_object_utils(reg_ro_access_seq)

  reg_write_seq write_seq;
  reg_read_seq  read_seq;

  rand int unsigned num_transactions;
  constraint c_num_transactions { num_transactions inside {[10:50]}; }

  function new(string name = "reg_ro_access_seq");
    super.new(name);
  endfunction

  virtual task body();
    int unsigned rand_index;
    logic [31:0] rand_data;

    write_seq = reg_write_seq::type_id::create("write_seq");
    read_seq  = reg_read_seq::type_id::create("read_seq");

    `uvm_info(get_type_name(),
      $sformatf("Starting Read-Only register test for %0d transactions, %0d RO regs...",
                num_transactions, NUM_RO_REGS),
      UVM_MEDIUM)

    repeat(num_transactions) begin
      // Pick a random RO register
      assert(std::randomize(rand_index) with { rand_index < NUM_RO_REGS; });
      assert(std::randomize(rand_data));

      // 1. Attempt a WRITE to RO register
      `uvm_info(get_type_name(),
        $sformatf("Attempt WRITE 0x%0h -> RO register %s (addr 0x%02h)",
                  rand_data, RO_REG_NAMES[rand_index], RO_REG_ADDRS[rand_index]),
        UVM_HIGH)

      write_seq.addr = RO_REG_ADDRS[rand_index];
      write_seq.data = rand_data;
      write_seq.start(m_sequencer);

      // 2. Read back (scoreboard checks value)
      read_seq.addr = RO_REG_ADDRS[rand_index];
      read_seq.start(m_sequencer);
    end

    `uvm_info(get_type_name(),
      "Read-Only register test finished.",
      UVM_MEDIUM)
  endtask
endclass


// =========================================================================
// Burst Register Test — write many registers, then read all back
// =========================================================================
class reg_burst_seq extends uvm_sequence #(wishbone_transaction);
  `uvm_object_utils(reg_burst_seq)

  reg_write_seq write_seq;
  reg_read_seq  read_seq;

  rand int unsigned num_write_transactions;
  constraint c_num_writes { num_write_transactions inside {[20:100]}; }

  function new(string name = "reg_burst_seq");
    super.new(name);
  endfunction

  virtual task body();
    logic [31:0] wdata, rdata;
    int unsigned rand_index;

    write_seq = reg_write_seq::type_id::create("write_seq");
    read_seq  = reg_read_seq::type_id::create("read_seq");

    `uvm_info(get_type_name(),
      $sformatf("--- STARTING BURST WRITE of %0d transactions ---", num_write_transactions),
      UVM_MEDIUM)

    // --- BURST WRITE PHASE ---
    repeat(num_write_transactions) begin
      assert(std::randomize(rand_index) with { rand_index < NUM_RW_REGS; });
      assert(std::randomize(wdata));

      // Special case: TX_BD_NUM must be 1-128
      if (RW_REG_ADDRS[rand_index] == 32'h20) begin
        wdata = wdata & 32'h7F;
        if (wdata == 0) wdata = 1;
      end

      write_seq.addr = RW_REG_ADDRS[rand_index];
      write_seq.data = wdata;
      write_seq.start(m_sequencer);
    end

    `uvm_info(get_type_name(),
      $sformatf("--- BURST WRITE finished. Starting BURST READ for %0d registers ---",
                NUM_RW_REGS),
      UVM_MEDIUM)

    // --- BURST READ PHASE ---
    for (int i = 0; i < NUM_RW_REGS; i++) begin
      read_seq.addr = RW_REG_ADDRS[i];
      read_seq.start(m_sequencer);
      rdata = read_seq.data;
      `uvm_info("SEQ", $sformatf("Burst read: %s (0x%02h) = 0x%0h",
                RW_REG_NAMES[i], RW_REG_ADDRS[i], rdata), UVM_HIGH)
    end

    `uvm_info(get_type_name(), "Register burst test finished.", UVM_MEDIUM)
  endtask : body

endclass : reg_burst_seq
