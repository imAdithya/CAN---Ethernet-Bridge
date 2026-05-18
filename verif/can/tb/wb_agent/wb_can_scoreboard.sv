`uvm_analysis_imp_decl(_wb)
`uvm_analysis_imp_decl(_can)

class wb_can_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(wb_can_scoreboard)

  uvm_analysis_imp_wb #(wb_can_trans, wb_can_scoreboard) wb_export;
  uvm_analysis_imp_can #(cb_trans_debug, wb_can_scoreboard) can_export;
  
  // Local register model for Wishbone side
  logic [7:0] reg_map [logic [7:0]];

  // Predicted Queue: Stores frames derived from Wishbone writes
  cb_trans_debug predicted_q[$];

  function new(string name, uvm_component parent);
    super.new(name, parent);
    wb_export = new("wb_export", this);
    can_export = new("can_export", this);
  endfunction

  // 1. Handle Wishbone Transactions (The "Source")
  virtual function void write_wb(wb_can_trans tx);
    if (tx.we) begin
      reg_map[tx.addr] = tx.data;
      
      // If a TX Command is issued (CMR register at 0x01, bit 4=Self TX or bit 0=TX)
      if (tx.addr == 8'h01 && (tx.data & 8'h11) != 8'h00) begin
        cb_trans_debug pred = cb_trans_debug::type_id::create("pred");
        
        // Map register values to predicted CAN frame
        pred.rtr = (reg_map[8'h10] & 8'h40) >> 6; // Bit 6 is RTR
        pred.dlc = reg_map[8'h10] & 4'hF;
        
        if ((reg_map[8'h10] & 8'h80) == 0) begin
          // SFF (Standard Frame Format)
          pred.ide = 0;
          pred.identifier[10:3] = reg_map[8'h11];
          pred.identifier[2:0]  = reg_map[8'h12] >> 5;
          
          // Predict Payload Data (SFF starts at 8'h13, only if not RTR)
          if (!pred.rtr) begin
            for (int i = 0; i < pred.dlc && i < 8; i++) begin
              pred.data[i] = reg_map[8'h13 + i];
            end
          end
          `uvm_info("SCB_PRED", $sformatf("New SFF frame predicted: ID=0x%03h RTR=%0b DLC=%0d", pred.identifier[10:0], pred.rtr, pred.dlc), UVM_LOW)
        end else begin
          // EFF (Extended Frame Format)
          pred.ide = 1;
          pred.identifier[28:21] = reg_map[8'h11];
          pred.identifier[20:13] = reg_map[8'h12];
          pred.identifier[12:5]  = reg_map[8'h13];
          pred.identifier[4:0]   = reg_map[8'h14] >> 3;
          
          // Predict Payload Data (EFF starts at 8'h15, only if not RTR)
          if (!pred.rtr) begin
            for (int i = 0; i < pred.dlc && i < 8; i++) begin
              pred.data[i] = reg_map[8'h15 + i];
            end
          end
          `uvm_info("SCB_PRED", $sformatf("New EFF frame predicted: ID=0x%08h RTR=%0b DLC=%0d", pred.identifier, pred.rtr, pred.dlc), UVM_LOW)
        end
        
        predicted_q.push_back(pred);
      end
    end
  endfunction

  // 2. Handle CAN Bus Transactions (The "Observation")
  virtual function void write_can(cb_trans_debug observed);
    cb_trans_debug expected;
    bit mismatch = 0;
    
    if (observed.is_rx) begin
      `uvm_info("SCB_E2E", "Ignoring injected RX frame in TX scoreboard.", UVM_HIGH)
      return;
    end
    
    if (predicted_q.size() == 0) begin
      `uvm_error("SCB_E2E", "Unexpected CAN frame observed on bus (no prediction exists)")
      return;
    end
    
    expected = predicted_q.pop_front();
    
    // Compare ID based on format (IDE)
    if (observed.ide != expected.ide) begin
      mismatch = 1;
      `uvm_error("SCB_E2E", $sformatf("FORMAT MISMATCH: Expected IDE=%0d, Observed IDE=%0d", expected.ide, observed.ide))
    end else if (expected.ide == 0) begin
      if (observed.identifier[10:0] != expected.identifier[10:0]) mismatch = 1;
    end else begin
      if (observed.identifier != expected.identifier) mismatch = 1;
    end
    
    // Compare DLC
    if (observed.dlc != expected.dlc) mismatch = 1;

    // Compare Payload Data (Only if NOT a Remote Frame)
    if (!expected.rtr) begin
      for (int i = 0; i < expected.dlc; i++) begin
        if (observed.data[i] != expected.data[i]) begin
          mismatch = 1;
          `uvm_error("SCB_E2E", $sformatf("DATA MISMATCH at Byte[%0d]: Expected=0x%0h Observed=0x%0h", i, expected.data[i], observed.data[i]))
        end
      end
    end else begin
      // Mathematically prove 0 payload bits exist by examining the entire unstuffed bitstream
      // Header length up to DLC:
      // SFF = 1(SOF)+11(ID)+1(RTR)+1(IDE)+1(r0)+4(DLC) = 19 bits
      // EFF = 1(SOF)+11(ID)+1(SRR)+1(IDE)+18(ID)+1(RTR)+1(r1)+1(r0)+4(DLC) = 39 bits
      int header_bits = (expected.ide == 0) ? 19 : 39;
      int crc_bits = 15;
      int expected_total = header_bits + crc_bits;
      int payload_bits = observed.unstuffed_bits.size() - expected_total;
      
      if (payload_bits > 0) begin
        mismatch = 1;
        `uvm_error("SCB_E2E", $sformatf("RTR PAYLOAD VIOLATION: Expected 0 payload bits, but found %0d bits between DLC and CRC! (Total bits: %0d)", payload_bits, observed.unstuffed_bits.size()))
      end else if (payload_bits < 0) begin
        mismatch = 1;
        `uvm_error("SCB_E2E", "RTR CORRUPTION: Bitstream is truncated before or during CRC.")
      end
      
      // Explicitly check the exact bit where RTR should be
      begin
        int rtr_idx = (expected.ide == 0) ? 12 : 32;
        if (observed.unstuffed_bits.size() > rtr_idx && observed.unstuffed_bits[rtr_idx] !== 1) begin
          mismatch = 1;
          `uvm_error("SCB_E2E", "RTR BIT CORRUPTION: RTR bit in raw wire bitstream is NOT 1!")
        end
      end
    end
    
    if (!mismatch) begin
      // Calculate explicitly the number of payload bits found on the wire
      int header_bits = (expected.ide == 0) ? 19 : 39;
      int payload_bits = observed.unstuffed_bits.size() - header_bits - 15;
      
      if (expected.ide == 0) begin
        if (expected.rtr == 1)
          `uvm_info("SCB_E2E", $sformatf("FULL MATCH (SFF REMOTE): ID=0x%03h DLC=%0d (Proved Payload Length=%0d bits) verified successfully!", observed.identifier[10:0], observed.dlc, payload_bits), UVM_LOW)
        else
          `uvm_info("SCB_E2E", $sformatf("FULL MATCH (SFF DATA): ID=0x%03h DLC=%0d (Proved Payload Length=%0d bits) Data=[0x%02h 0x%02h 0x%02h 0x%02h 0x%02h 0x%02h 0x%02h 0x%02h] verified successfully!", 
            observed.identifier[10:0], observed.dlc, payload_bits, observed.data[0], observed.data[1], observed.data[2], observed.data[3], observed.data[4], observed.data[5], observed.data[6], observed.data[7]), UVM_LOW)
      end else begin
        if (expected.rtr == 1)
          `uvm_info("SCB_E2E", $sformatf("FULL MATCH (EFF REMOTE): ID=0x%08h DLC=%0d (Proved Payload Length=%0d bits) verified successfully!", observed.identifier, observed.dlc, payload_bits), UVM_LOW)
        else
          `uvm_info("SCB_E2E", $sformatf("FULL MATCH (EFF DATA): ID=0x%08h DLC=%0d (Proved Payload Length=%0d bits) Data=[0x%02h 0x%02h 0x%02h 0x%02h 0x%02h 0x%02h 0x%02h 0x%02h] verified successfully!", 
            observed.identifier, observed.dlc, payload_bits, observed.data[0], observed.data[1], observed.data[2], observed.data[3], observed.data[4], observed.data[5], observed.data[6], observed.data[7]), UVM_LOW)
      end
    end else begin
      `uvm_error("SCB_E2E", $sformatf("FRAME MISMATCH: Expected IDE=%0d RTR=%0d ID=0x%08h DLC=%0d, Observed IDE=%0d RTR=%0d ID=0x%08h DLC=%0d", 
        expected.ide, expected.rtr, expected.identifier, expected.dlc, observed.ide, observed.rtr, observed.identifier, observed.dlc))
    end

  endfunction

endclass