class wb_can_fifo_rx_seq extends uvm_sequence#(wb_can_trans);
  `uvm_object_utils(wb_can_fifo_rx_seq)

  function new(string name = "wb_can_fifo_rx_seq");
    super.new(name);
  endfunction

  virtual task body();
    wb_can_trans req;
    logic [7:0] read_val;

    `uvm_info(get_name(), "--- REG-06 ADDENDUM: STARTING RX FIFO BANKING VERIFICATION ---", UVM_LOW)

    // Phase 1: Self Test Setup
    // Enter Reset Mode, switch to PeliCAN
    `uvm_info(get_name(), "Phase 1: Setting up PeliCAN and Self-Test Mode...", UVM_LOW)
    req = wb_can_trans::type_id::create("req");
    start_item(req); req.addr = 8'h1F; req.we = 1'b1; req.data = 8'h80; finish_item(req); // Extended Mode (CDR.7=1)

    // Setup Acceptance Filters to accept everything (so our self-transmitted frame isn't dropped)
    // In PeliCAN, AMR0-3 are at 0x14-0x17. Write 0xFF to accept all IDs.
    start_item(req); req.addr = 8'h14; req.we = 1'b1; req.data = 8'hFF; finish_item(req);
    start_item(req); req.addr = 8'h15; req.we = 1'b1; req.data = 8'hFF; finish_item(req);
    start_item(req); req.addr = 8'h16; req.we = 1'b1; req.data = 8'hFF; finish_item(req);
    start_item(req); req.addr = 8'h17; req.we = 1'b1; req.data = 8'hFF; finish_item(req);

    // Setup valid CAN Bit Timings (BTR0, BTR1) so the TX shift register functionally ticks!
    // Quantum = 2 clocks. TSEG1 = 5+1, TSEG2 = 2+1 -> 10 Quanta/Bit. 
    start_item(req); req.addr = 8'h06; req.we = 1'b1; req.data = 8'h00; finish_item(req); // BTR0
    start_item(req); req.addr = 8'h07; req.we = 1'b1; req.data = 8'h25; finish_item(req); // BTR1

    // Enter Operating Mode BUT enable Self-Test (MOD.2=1, MOD.0=0)
    // 0x04 = Self-Test (Bit 2 == 1). This loops TX internally to RX.
    start_item(req); req.addr = 8'h00; req.we = 1'b1; req.data = 8'h04; finish_item(req);

    // Phase 2: TX Load
    `uvm_info(get_name(), "Phase 2: Loading CAN Frame into TX Buffer (0x10-0x1C)...", UVM_LOW)
    // ID: Standard Format, EFF=0. DLC=4. Data=[0x11, 0x22, 0x33, 0x44]
    start_item(req); req.addr = 8'h10; req.we = 1'b1; req.data = 8'h04; finish_item(req); // Frame Info (SFF, 4 bytes)
    start_item(req); req.addr = 8'h11; req.we = 1'b1; req.data = 8'hAA; finish_item(req); // ID1
    start_item(req); req.addr = 8'h12; req.we = 1'b1; req.data = 8'h55; finish_item(req); // ID2
    start_item(req); req.addr = 8'h13; req.we = 1'b1; req.data = 8'h11; finish_item(req); // Data 1
    start_item(req); req.addr = 8'h14; req.we = 1'b1; req.data = 8'h22; finish_item(req); // Data 2
    start_item(req); req.addr = 8'h15; req.we = 1'b1; req.data = 8'h33; finish_item(req); // Data 3
    start_item(req); req.addr = 8'h16; req.we = 1'b1; req.data = 8'h44; finish_item(req); // Data 4

    // Phase 3: Transmit Command
    `uvm_info(get_name(), "Phase 3: Issuing Self-Transmission Command (CMR = 0x10)...", UVM_LOW)
    // Self-Reception request is Bit 4 in Command Reg (0x01 = 0x10)
    start_item(req); req.addr = 8'h01; req.we = 1'b1; req.data = 8'h10; finish_item(req);

    // Poll the Status Register (0x02) until Transmission Complete (Bit 3) asserts.
    `uvm_info(get_name(), "Polling Status Register (0x02) for Transmission Complete (Bit 3)...", UVM_LOW)
    read_val = 8'h00;
    while ((read_val & 8'h08) == 8'h00) begin
      #10000; // wait ~10us between polls
      start_item(req); req.addr = 8'h02; req.we = 1'b0; finish_item(req);
      read_val = req.data;
      if ((read_val & 8'hE0) == 8'h60) begin 
         `uvm_warning(get_name(), "Status check shows core is in ERROR PASSIVE/BUS OFF state!")
      end
    end
    `uvm_info(get_name(), "Transmission completed successfully!", UVM_LOW)

    // Phase 4: RX Readback
    `uvm_info(get_name(), "Phase 4: Reading RX FIFO from the identical 0x10-0x1C alias window...", UVM_LOW)
    
    // Read 0x10 (Frame Info). Should be 0x04 (DLC=4)
    start_item(req); req.addr = 8'h10; req.we = 1'b0; finish_item(req);
    read_val = req.data;
    if (read_val !== 8'h04) `uvm_error("RX_FAIL", $sformatf("RX Frame Info mismatch! Expected 0x04, Got 0x%0x", read_val))

    // Read 0x11 (ID1). Should be 0xAA
    start_item(req); req.addr = 8'h11; req.we = 1'b0; finish_item(req);
    read_val = req.data;
    if (read_val !== 8'hAA) `uvm_error("RX_FAIL", $sformatf("RX ID1 mismatch! Expected 0xAA, Got 0x%0x", read_val))

    // Read 0x12 (ID2). For SFF, only the top 3 bits [7:5] hold ID2-ID0. The rest are truncated to 0 by hardware!
    // We wrote 0x55 (0101_0101). The MSBs are 010. So it should read back 0100_0000 (0x40).
    start_item(req); req.addr = 8'h12; req.we = 1'b0; finish_item(req);
    read_val = req.data;
    if ((read_val & 8'hE0) !== (8'h55 & 8'hE0)) `uvm_error("RX_FAIL", $sformatf("RX ID2 mismatch! Expected 0x40, Got 0x%0x", read_val))

    // Read 0x13 (Data 1). Should be 0x11
    start_item(req); req.addr = 8'h13; req.we = 1'b0; finish_item(req);
    read_val = req.data;
    if (read_val !== 8'h11) `uvm_error("RX_FAIL", $sformatf("RX Data 1 mismatch! Expected 0x11, Got 0x%0x", read_val))

    // Read 0x14 (Data 2). Should be 0x22
    start_item(req); req.addr = 8'h14; req.we = 1'b0; finish_item(req);
    read_val = req.data;
    if (read_val !== 8'h22) `uvm_error("RX_FAIL", $sformatf("RX Data 2 mismatch! Expected 0x22, Got 0x%0x", read_val))

    // Read 0x15 (Data 3). Should be 0x33
    start_item(req); req.addr = 8'h15; req.we = 1'b0; finish_item(req);
    read_val = req.data;
    if (read_val !== 8'h33) `uvm_error("RX_FAIL", $sformatf("RX Data 3 mismatch! Expected 0x33, Got 0x%0x", read_val))

    // Read 0x16 (Data 4). Should be 0x44
    start_item(req); req.addr = 8'h16; req.we = 1'b0; finish_item(req);
    read_val = req.data;
    if (read_val !== 8'h44) `uvm_error("RX_FAIL", $sformatf("RX Data 4 mismatch! Expected 0x44, Got 0x%0x", read_val))

    `uvm_info(get_name(), "All RX FIFO fields perfectly retrieved from alias window!", UVM_MEDIUM)
    `uvm_info(get_name(), "--- REG-06 ADDENDUM: RX FIFO BANKING VERIFICATION COMPLETE ---", UVM_LOW)

  endtask
endclass
