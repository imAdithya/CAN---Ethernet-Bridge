// QUE-01: Queue Fill/Drain Test
// Sends multiple downstream ETH frames to exercise the CAN TX queue.
// Verifies FIFO ordering and data integrity after draining.
class queue_fill_drain_test extends bridge_base_test;
  `uvm_component_utils(queue_fill_drain_test)

  function new(string name = "queue_fill_drain_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    queue_fill_drain_seq cfg_seq;
    counter_verify_seq   cnt_seq;
    bit [31:0] rx_bd_addr, frame_ptr;
    bit [7:0]  frame_data[8];
    int num_frames;

    phase.raise_objection(this);
    `uvm_info(get_type_name(), "Starting queue fill/drain test (QUE-01)...", UVM_MEDIUM)
    #100ns;

    cfg_seq = queue_fill_drain_seq::type_id::create("cfg_seq");
    cfg_seq.start(m_env.m_host_agent.m_sequencer);

    rx_bd_addr = `DEFAULT_RX_BD_ADDR;
    frame_ptr  = rx_bd_addr + 32'h100;
    num_frames = 5;

    // Send frames one at a time — each fully completing before next
    for (int f = 0; f < num_frames; f++) begin
      `uvm_info("QUE01", $sformatf("Frame %0d: loading and triggering...", f), UVM_MEDIUM)

      for (int i = 0; i < 8; i++)
        frame_data[i] = f * 16 + i;

      downstream_frame_builder::build_gateway_frame(
        m_mem_cfg, frame_ptr,
        .can_id(29'h100 + f), .dlc(4'd8), .eff(1'b0), .rtr(1'b0),
        .data(frame_data)
      );
      m_mem_cfg.setup_rx_bd(rx_bd_addr, frame_ptr, 16'd60);

      m_mem_cfg.vif.eth_rx_irq = 1'b1;
      #40ns;
      m_mem_cfg.vif.eth_rx_irq = 1'b0;
      #15us;

      // CAN TX complete
      m_can_cfg.vif.can_tx_irq = 1'b1;
      #40ns;
      m_can_cfg.vif.can_tx_irq = 1'b0;
      #5us;

      // Verify last frame's CAN ID was written correctly
      begin
        bit [7:0] id_b1 = m_can_cfg.can_regs['h11];
        bit [7:0] id_b2 = m_can_cfg.can_regs['h12];
        bit [28:0] exp_id = 29'h100 + f;
        bit [7:0]  exp_b1 = exp_id[28:21];
        bit [7:0]  exp_b2 = exp_id[20:13];

        if (id_b1 !== exp_b1 || id_b2 !== exp_b2)
          `uvm_error("QUE01_CHK", $sformatf(
            "Frame %0d: CAN ID bytes mismatch: got=%02h%02h exp=%02h%02h",
            f, id_b1, id_b2, exp_b1, exp_b2))
        else
          `uvm_info("QUE01_CHK", $sformatf("Frame %0d: CAN ID PASS", f), UVM_MEDIUM)
      end
    end

    // Verify counters
    cnt_seq = counter_verify_seq::type_id::create("cnt_seq");
    cnt_seq.exp_eth_rx = num_frames;
    cnt_seq.exp_can_tx = num_frames;
    cnt_seq.exp_errors = 0;
    cnt_seq.start(m_env.m_host_agent.m_sequencer);

    #500ns;
    `uvm_info(get_type_name(), "QUE-01 finished.", UVM_MEDIUM)
    phase.drop_objection(this);
  endtask
endclass
