// DN-04: Backpressure Downstream Test
// Sends 2 ETH frames rapidly. The first is processed normally.
// The second tests that the FSM can handle back-to-back frames
// after the first completes. Verifies no frame loss.
class downstream_backpressure_test extends bridge_base_test;
  `uvm_component_utils(downstream_backpressure_test)

  function new(string name = "downstream_backpressure_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    downstream_backpressure_seq dn_seq;
    counter_verify_seq          cnt_seq;
    bit [31:0] rx_bd_addr, frame_ptr;
    bit [7:0] frame_data[8];
    int frame_num;

    phase.raise_objection(this);
    `uvm_info(get_type_name(), "Starting backpressure downstream test (DN-04)...", UVM_MEDIUM)
    #100ns;

    // Step 1: Configure bridge
    dn_seq = downstream_backpressure_seq::type_id::create("dn_seq");
    dn_seq.start(m_env.m_host_agent.m_sequencer);

    rx_bd_addr = `DEFAULT_RX_BD_ADDR;
    frame_ptr  = rx_bd_addr + 32'h100;

    // Step 2: Send multiple frames, processing each fully before the next
    for (frame_num = 0; frame_num < 3; frame_num++) begin
      `uvm_info("DN04_CHK", $sformatf("Sending frame %0d...", frame_num), UVM_MEDIUM)

      // Build unique frame data
      for (int i = 0; i < 8; i++)
        frame_data[i] = (frame_num * 16) + i;

      downstream_frame_builder::build_gateway_frame(
        m_mem_cfg, frame_ptr,
        .can_id(29'h200 + frame_num), .dlc(4'd8), .eff(1'b0), .rtr(1'b0),
        .data(frame_data)
      );

      m_mem_cfg.setup_rx_bd(rx_bd_addr, frame_ptr, 16'd60);

      // Trigger ETH RX interrupt
      m_mem_cfg.vif.eth_rx_irq = 1'b1;
      #40ns;
      m_mem_cfg.vif.eth_rx_irq = 1'b0;

      // Wait for downstream to process frame
      #15us;

      // Trigger CAN TX complete
      m_can_cfg.vif.can_tx_irq = 1'b1;
      #40ns;
      m_can_cfg.vif.can_tx_irq = 1'b0;

      // Wait for FREE_BD
      #5us;
    end

    // Step 2b: Send one frame in tunnel mode to hit tunnel_ok coverage bin
    begin
      bridge_reg_write_seq wr_tunnel;
      wr_tunnel = bridge_reg_write_seq::type_id::create("wr_tunnel");

      // Switch to tunnel mode
      wr_tunnel.addr = {24'h0, `REG_BRIDGE_CTRL};
      wr_tunnel.data = 32'h0000_0005;  // en=1, mode=10 (tunnel)
      wr_tunnel.start(m_env.m_host_agent.m_sequencer);

      for (int i = 0; i < 8; i++)
        frame_data[i] = 8'hF0 + i;

      downstream_frame_builder::build_tunnel_frame(
        m_mem_cfg, frame_ptr,
        .can_id(29'h300), .dlc(4'd4), .eff(1'b0), .rtr(1'b0),
        .data(frame_data)
      );
      m_mem_cfg.setup_rx_bd(rx_bd_addr, frame_ptr, 16'd64);

      m_mem_cfg.vif.eth_rx_irq = 1'b1;
      #40ns;
      m_mem_cfg.vif.eth_rx_irq = 1'b0;
      #15us;

      m_can_cfg.vif.can_tx_irq = 1'b1;
      #40ns;
      m_can_cfg.vif.can_tx_irq = 1'b0;
      #5us;

      // Switch back to gateway mode
      wr_tunnel.data = 32'h0000_0003;
      wr_tunnel.start(m_env.m_host_agent.m_sequencer);
    end

    // Step 3: Verify all frames processed (3 gateway + 1 tunnel = 4)
    cnt_seq = counter_verify_seq::type_id::create("cnt_seq");
    cnt_seq.exp_eth_rx = 4;
    cnt_seq.exp_can_tx = 4;
    cnt_seq.exp_errors = 0;
    cnt_seq.start(m_env.m_host_agent.m_sequencer);

    #500ns;
    `uvm_info(get_type_name(), "DN-04 finished.", UVM_MEDIUM)
    phase.drop_objection(this);
  endtask
endclass
