// bridge_system_seq.sv — System-level and infrastructure sequences
// Covers tests: QUE-01, ARB-01, SYS-01, SYS-02, SYS-03, SYS-04


// =========================================================================
// QUE-01: Queue Fill/Drain Sequence (config only — test drives frames)
// =========================================================================
class queue_fill_drain_seq extends uvm_sequence #(wishbone_transaction);
  `uvm_object_utils(queue_fill_drain_seq)

  bridge_reg_write_seq wr_seq;

  function new(string name = "queue_fill_drain_seq");
    super.new(name);
  endfunction

  virtual task body();
    `uvm_info(get_type_name(), "QUE-01: Configuring bridge for queue test...", UVM_MEDIUM)
    wr_seq = bridge_reg_write_seq::type_id::create("wr_seq");

    wr_seq.addr = {24'h0, `REG_BRIDGE_CTRL};
    wr_seq.data = 32'h0000_0003;
    wr_seq.start(m_sequencer);

    wr_seq.addr = {24'h0, `REG_FILTER_CTRL};
    wr_seq.data = 32'h0000_0000;
    wr_seq.start(m_sequencer);

    `uvm_info(get_type_name(), "QUE-01: Config complete.", UVM_MEDIUM)
  endtask
endclass


// =========================================================================
// ARB-01: Arbiter Contention Sequence (config only)
// =========================================================================
class arbiter_contention_seq extends uvm_sequence #(wishbone_transaction);
  `uvm_object_utils(arbiter_contention_seq)

  bridge_reg_write_seq wr_seq;

  function new(string name = "arbiter_contention_seq");
    super.new(name);
  endfunction

  virtual task body();
    `uvm_info(get_type_name(), "ARB-01: Configuring bridge for arbiter test...", UVM_MEDIUM)
    wr_seq = bridge_reg_write_seq::type_id::create("wr_seq");

    wr_seq.addr = {24'h0, `REG_BRIDGE_CTRL};
    wr_seq.data = 32'h0000_0003;
    wr_seq.start(m_sequencer);

    wr_seq.addr = {24'h0, `REG_FILTER_CTRL};
    wr_seq.data = 32'h0000_0000;
    wr_seq.start(m_sequencer);

    `uvm_info(get_type_name(), "ARB-01: Config complete.", UVM_MEDIUM)
  endtask
endclass


// =========================================================================
// SYS-01: Upstream End-to-End Sequence (config only)
// =========================================================================
class sys_upstream_e2e_seq extends uvm_sequence #(wishbone_transaction);
  `uvm_object_utils(sys_upstream_e2e_seq)

  bridge_reg_write_seq wr_seq;

  function new(string name = "sys_upstream_e2e_seq");
    super.new(name);
  endfunction

  virtual task body();
    `uvm_info(get_type_name(), "SYS-01: Configuring bridge for upstream E2E...", UVM_MEDIUM)
    wr_seq = bridge_reg_write_seq::type_id::create("wr_seq");

    wr_seq.addr = {24'h0, `REG_BRIDGE_CTRL};
    wr_seq.data = 32'h0000_0003;
    wr_seq.start(m_sequencer);

    wr_seq.addr = {24'h0, `REG_FILTER_CTRL};
    wr_seq.data = 32'h0000_0000;
    wr_seq.start(m_sequencer);

    `uvm_info(get_type_name(), "SYS-01: Config complete.", UVM_MEDIUM)
  endtask
endclass


// =========================================================================
// SYS-02: Downstream End-to-End Sequence (config only)
// =========================================================================
class sys_downstream_e2e_seq extends uvm_sequence #(wishbone_transaction);
  `uvm_object_utils(sys_downstream_e2e_seq)

  bridge_reg_write_seq wr_seq;

  function new(string name = "sys_downstream_e2e_seq");
    super.new(name);
  endfunction

  virtual task body();
    `uvm_info(get_type_name(), "SYS-02: Configuring bridge for downstream E2E...", UVM_MEDIUM)
    wr_seq = bridge_reg_write_seq::type_id::create("wr_seq");

    wr_seq.addr = {24'h0, `REG_BRIDGE_CTRL};
    wr_seq.data = 32'h0000_0003;
    wr_seq.start(m_sequencer);

    wr_seq.addr = {24'h0, `REG_FILTER_CTRL};
    wr_seq.data = 32'h0000_0000;
    wr_seq.start(m_sequencer);

    `uvm_info(get_type_name(), "SYS-02: Config complete.", UVM_MEDIUM)
  endtask
endclass


// =========================================================================
// SYS-03: Full Duplex Sequence (config only)
// =========================================================================
class sys_fullduplex_seq extends uvm_sequence #(wishbone_transaction);
  `uvm_object_utils(sys_fullduplex_seq)

  bridge_reg_write_seq wr_seq;

  function new(string name = "sys_fullduplex_seq");
    super.new(name);
  endfunction

  virtual task body();
    `uvm_info(get_type_name(), "SYS-03: Configuring bridge for full-duplex...", UVM_MEDIUM)
    wr_seq = bridge_reg_write_seq::type_id::create("wr_seq");

    wr_seq.addr = {24'h0, `REG_BRIDGE_CTRL};
    wr_seq.data = 32'h0000_0003;
    wr_seq.start(m_sequencer);

    wr_seq.addr = {24'h0, `REG_FILTER_CTRL};
    wr_seq.data = 32'h0000_0000;
    wr_seq.start(m_sequencer);

    `uvm_info(get_type_name(), "SYS-03: Config complete.", UVM_MEDIUM)
  endtask
endclass


// =========================================================================
// SYS-04: Full Duplex Stress Sequence (config only)
// =========================================================================
class sys_fullduplex_stress_seq extends uvm_sequence #(wishbone_transaction);
  `uvm_object_utils(sys_fullduplex_stress_seq)

  bridge_reg_write_seq wr_seq;

  function new(string name = "sys_fullduplex_stress_seq");
    super.new(name);
  endfunction

  virtual task body();
    `uvm_info(get_type_name(), "SYS-04: Configuring bridge for full-duplex stress...", UVM_MEDIUM)
    wr_seq = bridge_reg_write_seq::type_id::create("wr_seq");

    wr_seq.addr = {24'h0, `REG_BRIDGE_CTRL};
    wr_seq.data = 32'h0000_0003;
    wr_seq.start(m_sequencer);

    wr_seq.addr = {24'h0, `REG_FILTER_CTRL};
    wr_seq.data = 32'h0000_0000;
    wr_seq.start(m_sequencer);

    `uvm_info(get_type_name(), "SYS-04: Config complete.", UVM_MEDIUM)
  endtask
endclass
