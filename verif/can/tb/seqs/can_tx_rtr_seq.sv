// TX-03: Remote Transmission Request (RTR) Sequence
// Configures DUT in PeliCAN mode, transmits remote frames (RTR=1) for both
// Standard (SFF) and Extended (EFF) formats, and verifies framing.
//
// Coverage targets:
//   - RTR bit set
//   - Verify DLC represents requested length, but data field is omitted.

class can_tx_rtr_seq extends uvm_sequence#(wb_can_trans);
  `uvm_object_utils(can_tx_rtr_seq)

  function new(string name = "can_tx_rtr_seq");
    super.new(name);
  endfunction

  // Helper: Write a register via Wishbone
  task wb_write(bit [7:0] addr, bit [7:0] data);
    wb_can_trans req = wb_can_trans::type_id::create("req");
    start_item(req);
    req.addr = addr;
    req.we   = 1'b1;
    req.data = data;
    req.sel  = 4'h1;
    finish_item(req);
  endtask

  // Helper: Read a register via Wishbone, return data
  task wb_read(bit [7:0] addr, output logic [7:0] data);
    wb_can_trans req = wb_can_trans::type_id::create("req");
    start_item(req);
    req.addr = addr;
    req.we   = 1'b0;
    req.data = 8'h00;
    req.sel  = 4'h1;
    finish_item(req);
    data = req.data;
  endtask

  // Helper: Poll status register until TX complete
  task wait_tx_complete();
    logic [7:0] status;
    int timeout = 500;
    status = 8'h00;
    while ((status & 8'h08) == 8'h00) begin
      #5000;  // 5us between polls
      wb_read(8'h02, status);
      timeout--;
      if (timeout == 0) begin
        `uvm_error("TX_TIMEOUT", "Transmission did not complete within timeout!")
        return;
      end
      if ((status & 8'h80) != 8'h00)
        `uvm_warning("TX_RTR", $sformatf("Bus-Off detected! Status=0x%0h", status))
    end
  endtask

  // Transmit SFF Remote Frame
  task transmit_sff_rtr(bit [10:0] can_id, bit [3:0] dlc);
    bit [7:0] frame_info, id1, id2;

    // SJA1000 PeliCAN SFF: 0x10.7 = FF(0), 0x10.6 = RTR(1)
    frame_info = {1'b0, 1'b1, 2'b00, dlc};
    id1 = can_id[10:3];
    id2 = {can_id[2:0], 5'b00000};

    `uvm_info("TX_RTR", $sformatf("Loading SFF RTR: ID=0x%03h Requested DLC=%0d", can_id, dlc), UVM_LOW)

    wb_write(8'h10, frame_info);
    wb_write(8'h11, id1);
    wb_write(8'h12, id2);

    // *Crucially*, we do NOT write any payload to 0x13
    wb_write(8'h01, 8'h10); // Self-TX Command
    wait_tx_complete();
    `uvm_info("TX_RTR", $sformatf("SFF RTR complete: ID=0x%03h", can_id), UVM_LOW)
  endtask

  // Transmit EFF Remote Frame
  task transmit_eff_rtr(bit [28:0] can_id, bit [3:0] dlc);
    bit [7:0] frame_info, id1, id2, id3, id4;

    // SJA1000 PeliCAN EFF: 0x10.7 = FF(1), 0x10.6 = RTR(1)
    frame_info = {1'b1, 1'b1, 2'b00, dlc};
    id1 = can_id[28:21];
    id2 = can_id[20:13];
    id3 = can_id[12:5];
    id4 = {can_id[4:0], 3'b000};

    `uvm_info("TX_RTR", $sformatf("Loading EFF RTR: ID=0x%08h Requested DLC=%0d", can_id, dlc), UVM_LOW)

    wb_write(8'h10, frame_info);
    wb_write(8'h11, id1);
    wb_write(8'h12, id2);
    wb_write(8'h13, id3);
    wb_write(8'h14, id4);

    // *Crucially*, we do NOT write any payload to 0x15
    wb_write(8'h01, 8'h10); // Self-TX Command
    wait_tx_complete();
    `uvm_info("TX_RTR", $sformatf("EFF RTR complete: ID=0x%08h", can_id), UVM_LOW)
  endtask


  virtual task body();
    logic [7:0] read_val;

    `uvm_info(get_name(), "=== TX-03: REMOTE TRANSMISSION REQUEST (RTR) TEST START ===", UVM_LOW)

    // Phase 1: Configure PeliCAN Mode
    wb_write(8'h00, 8'h01);
    wb_write(8'h1F, 8'h80);
    wb_write(8'h14, 8'hFF);  
    wb_write(8'h15, 8'hFF);  
    wb_write(8'h16, 8'hFF);  
    wb_write(8'h17, 8'hFF);  
    wb_write(8'h06, 8'h00);  
    wb_write(8'h07, 8'h25);  
    wb_write(8'h00, 8'h04);
    #1000;

    // Phase 2: SFF Remote Frames
    transmit_sff_rtr(11'h0F0, 4'd1); #2000;
    transmit_sff_rtr(11'h123, 4'd4); #2000;
    transmit_sff_rtr(11'h7FF, 4'd8); #2000;

    // Phase 3: EFF Remote Frames
    transmit_eff_rtr(29'h00000001, 4'd2); #2000;
    transmit_eff_rtr(29'h1AAAAAAA, 4'd6); #2000;
    transmit_eff_rtr(29'h1FFFFFFF, 4'd8); #2000;

    `uvm_info(get_name(), "=== TX-03: RTR TEST COMPLETE ===", UVM_LOW)
  endtask
endclass
