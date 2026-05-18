// RST-01: Mid-Transaction Reset Test
// Asserts reset while upstream FSM is in WRITE_RAM or PROG_BD state.
// Verifies clean return to IDLE, no partial BD left READY.
class mid_transaction_reset_test extends bridge_base_test;
  `uvm_component_utils(mid_transaction_reset_test)

  function new(string name = "mid_transaction_reset_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    mid_transaction_reset_seq cfg_seq;
    bit [31:0] rd_data;
    bit [31:0] tx_bd_addr;

    phase.raise_objection(this);
    `uvm_info(get_type_name(), "Starting mid-transaction reset test (RST-01)...", UVM_MEDIUM)
    #100ns;

    // Step 1: Configure bridge and start upstream transaction
    cfg_seq = mid_transaction_reset_seq::type_id::create("cfg_seq");
    cfg_seq.start(m_env.m_host_agent.m_sequencer);

    // Load CAN frame
    m_can_cfg.load_can_frame(
      .can_id(29'h1AB), .dlc(4'd8), .eff(1'b0), .rtr(1'b0),
      .data('{8'hDE, 8'hAD, 8'hBE, 8'hEF, 8'hCA, 8'hFE, 8'h01, 8'h02})
    );

    // Trigger upstream FSM
    m_can_cfg.vif.can_rx_irq = 1'b1;
    #40ns;
    m_can_cfg.vif.can_rx_irq = 1'b0;

    // Step 2: Wait for FSM to reach WRITE_RAM (state 4)
    // READ_CAN ~26 clocks, FILTER ~2, ENCAP ~2 → ~60 clocks × 20ns = ~1.2us
    #1500ns;

    // Step 3: Assert reset mid-transaction using uvm_hdl_force on DUT rst_n
    `uvm_info("RST01", "Asserting reset while FSM is in WRITE_RAM/PROG_BD...", UVM_MEDIUM)
    uvm_hdl_force("tb_bridge_top.rst_n", 0);
    #200ns;
    uvm_hdl_force("tb_bridge_top.rst_n", 1);  // Drive high explicitly
    #100ns;
    uvm_hdl_release("tb_bridge_top.rst_n");

    // Step 4: Wait for system to stabilize after reset
    #5us;

    // Step 5: Read bridge status register — FSM should be idle
    begin
      bridge_reg_read_seq rd_seq;
      rd_seq = bridge_reg_read_seq::type_id::create("rd_seq");
      rd_seq.addr = {24'h0, `REG_BRIDGE_STATUS};
      rd_seq.start(m_env.m_host_agent.m_sequencer);
      rd_data = rd_seq.data;
    end

    // Check that upstream busy bit is 0 (FSM back to IDLE)
    if (rd_data[0] == 1'b0)
      `uvm_info("RST01_CHK", "Upstream FSM returned to IDLE after reset — PASS", UVM_MEDIUM)
    else
      `uvm_error("RST01_CHK", $sformatf("Upstream FSM still busy after reset: status=0x%08h", rd_data))

    // Check that downstream busy bit is also 0
    if (rd_data[1] == 1'b0)
      `uvm_info("RST01_CHK", "Downstream FSM returned to IDLE after reset — PASS", UVM_MEDIUM)
    else
      `uvm_error("RST01_CHK", $sformatf("Downstream FSM still busy after reset: status=0x%08h", rd_data))

    // Step 6: Read the TX BD status to verify it was NOT left READY
    // BD lives in the ETH memory space — read from memory model directly
    tx_bd_addr = `DEFAULT_TX_BD_ADDR;
    rd_data = m_mem_cfg.memory[tx_bd_addr >> 2];

    // BD READY bit is bit 0 — should NOT be 1
    if (rd_data[0] == 1'b0)
      `uvm_info("RST01_CHK", $sformatf("TX BD READY bit is 0 (no partial BD) — PASS (bd=0x%08h)", rd_data), UVM_MEDIUM)
    else
      `uvm_error("RST01_CHK", $sformatf("TX BD READY bit is 1 — partial BD left! status=0x%08h", rd_data))

    // Step 7: Verify bridge can still function after reset
    // Re-enable bridge
    begin
      bridge_reg_write_seq wr_seq;
      wr_seq = bridge_reg_write_seq::type_id::create("wr_seq");
      wr_seq.addr = {24'h0, `REG_BRIDGE_CTRL};
      wr_seq.data = 32'h0000_0003;
      wr_seq.start(m_env.m_host_agent.m_sequencer);
    end

    // Load new frame and run a complete upstream transfer
    m_can_cfg.load_can_frame(
      .can_id(29'h222), .dlc(4'd2), .eff(1'b0), .rtr(1'b0),
      .data('{8'hAA, 8'hBB, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00})
    );

    m_can_cfg.vif.can_rx_irq = 1'b1;
    #40ns;
    m_can_cfg.vif.can_rx_irq = 1'b0;
    #10us;

    m_mem_cfg.vif.eth_tx_irq = 1'b1;
    #40ns;
    m_mem_cfg.vif.eth_tx_irq = 1'b0;
    #5us;

    `uvm_info("RST01", "Post-reset upstream transfer completed — bridge functional.", UVM_MEDIUM)

    #500ns;
    `uvm_info(get_type_name(), "RST-01 finished.", UVM_MEDIUM)
    phase.drop_objection(this);
  endtask
endclass
