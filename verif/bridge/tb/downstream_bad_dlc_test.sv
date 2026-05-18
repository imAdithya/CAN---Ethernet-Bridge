// DN-03: Bad DLC Downstream Test
// Receives an Ethernet frame with DLC > 8. Verifies frame is dropped
// during DECAP stage and cnt_errors incremented.
class downstream_bad_dlc_test extends bridge_base_test;
  `uvm_component_utils(downstream_bad_dlc_test)

  function new(string name = "downstream_bad_dlc_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    downstream_bad_dlc_seq dn_seq;
    counter_verify_seq     cnt_seq;
    bit [31:0] rx_bd_addr, frame_ptr;
    int dlc_val;

    phase.raise_objection(this);
    `uvm_info(get_type_name(), "Starting bad DLC downstream test (DN-03)...", UVM_MEDIUM)
    #100ns;

    // Step 1: Configure bridge
    dn_seq = downstream_bad_dlc_seq::type_id::create("dn_seq");
    dn_seq.start(m_env.m_host_agent.m_sequencer);

    rx_bd_addr = `DEFAULT_RX_BD_ADDR;
    frame_ptr  = rx_bd_addr + 32'h100;

    // Step 2: Test DLC values 9, 12, 15 (all invalid)
    for (dlc_val = 9; dlc_val <= 15; dlc_val = dlc_val + 3) begin
      `uvm_info("DN03_CHK", $sformatf("Testing invalid DLC=%0d...", dlc_val), UVM_MEDIUM)

      // Build frame with bad DLC
      downstream_frame_builder::build_bad_dlc_frame(
        m_mem_cfg, frame_ptr, dlc_val[3:0]
      );

      // Set up RX BD
      m_mem_cfg.setup_rx_bd(rx_bd_addr, frame_ptr, 16'd60);

      // Trigger ETH RX interrupt
      m_mem_cfg.vif.eth_rx_irq = 1'b1;
      #40ns;
      m_mem_cfg.vif.eth_rx_irq = 1'b0;

      // Wait for FSM to read, validate, decap (fail), free BD
      #15us;
    end

    // Step 3: Verify counters — 3 ETH RX, 0 CAN TX, 3 errors
    cnt_seq = counter_verify_seq::type_id::create("cnt_seq");
    cnt_seq.exp_eth_rx = 3;
    cnt_seq.exp_can_tx = 0;
    cnt_seq.exp_errors = 3;
    cnt_seq.start(m_env.m_host_agent.m_sequencer);

    #500ns;
    `uvm_info(get_type_name(), "DN-03 finished.", UVM_MEDIUM)
    phase.drop_objection(this);
  endtask
endclass
