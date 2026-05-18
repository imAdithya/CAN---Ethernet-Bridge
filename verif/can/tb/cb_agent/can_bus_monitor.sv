`timescale 1ns/10ps

// CAN Bus Monitor - Enhanced for Protocol-Correctness and Clean Reporting
class can_bus_monitor extends uvm_monitor;
  can_vif vif;
  `uvm_component_utils(can_bus_monitor)

  uvm_analysis_port #(cb_trans_debug) item_collected_port;

  // Internal state for stuff-bit detection
  bit last_bit;
  int same_bit_count;
  int stuff_bits_count; 
  
  bit raw_bits[$];
  bit unstuffed_bits[$];

  function new(string name, uvm_component parent);
    super.new(name, parent);
    item_collected_port = new("item_collected_port", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    vif = can_bus_pkg::static_vif;
  endfunction

  // Helper: Convert bit queue to clean Hex string (Big-Endian bit order)
  function string bits_to_hex(bit q[$]);
    string s = "";
    bit [3:0] nibble;
    int len = q.size();
    
    for (int i = 0; i < len; i += 4) begin
      nibble = 0;
      for (int j = 0; j < 4; j++) begin
        if (i + j < len) begin
          nibble[3-j] = q[i+j];
        end
      end
      s = {s, $sformatf("%h", nibble)};
    end
    return s;
  endfunction

  // Capture a raw bit from the wire
  task get_raw_bit(output bit b);
    repeat(vif.bit_time_clks / 2) @(posedge vif.clk);
    b = vif.can_bus; // Sample the shared bus
    raw_bits.push_back(b);
    repeat(vif.bit_time_clks / 2) @(posedge vif.clk);
  endtask

  // Capture a bit and perform unstuffing
  task get_unstuffed_bit(output bit b);
    bit raw_v;
    get_raw_bit(raw_v);
    
    if (same_bit_count == 5) begin
      // Discard the stuff bit (it must be opposite polarity)
      stuff_bits_count++;
      `uvm_info("CAN_STUFF", $sformatf("Stuff bit (%b) removed at bit position %0d", raw_v, raw_bits.size()), UVM_DEBUG)
      
      // Update state based on the stuff bit 
      last_bit = raw_v; 
      same_bit_count = 1;

      // Now read the actual data bit
      get_raw_bit(raw_v);
    end

    b = raw_v;
    if (b == last_bit) begin
      same_bit_count++;
    end else begin
      last_bit = b;
      same_bit_count = 1;
    end
    unstuffed_bits.push_back(b);
  endtask

  virtual task run_phase(uvm_phase phase);
    cb_trans_debug tr;
    bit b;
    
    forever begin
      // 1. Wait for Start-of-Frame (Falling edge on bus)
      @(negedge vif.can_bus);
      tr = cb_trans_debug::type_id::create("tr");
      
      // Determine source: If vif.can_rx is low, the agent is driving it
      tr.is_rx = (vif.can_rx == 0);
      
      `uvm_info("CAN_MON", $sformatf("SOF detected! Source: %s", tr.is_rx ? "AGENT_INJECT" : "DUT_TX"), UVM_HIGH)
      
      // Reset counters for new frame
      raw_bits.delete();
      unstuffed_bits.delete();
      stuff_bits_count = 0;

      // Sync to mid-SOF
      repeat(vif.bit_time_clks / 2) @(posedge vif.clk);
      if (vif.can_bus != 0) begin
        `uvm_warning("CAN_MON", "SOF glitch detected!")
        continue; 
      end
      
      raw_bits.push_back(0); 
      repeat(vif.bit_time_clks / 2) @(posedge vif.clk);

      // Initialize state with SOF (0)
      last_bit = 0; 
      same_bit_count = 1;
      unstuffed_bits.push_back(0);

      // 2. Decode Base Identifier (11 bits)
      begin
        bit [10:0] base_id;
        for (int i = 10; i >= 0; i--) begin
          get_unstuffed_bit(b);
          base_id[i] = b;
        end
        
        // 3. SRR/RTR bit
        get_unstuffed_bit(b); 
        tr.rtr = b; // Temporarily store as RTR (it's SRR if EFF)

        // 4. IDE bit
        get_unstuffed_bit(b); 
        tr.ide = b;

        if (tr.ide == 0) begin
          // SFF: identifier is 11 bits
          tr.identifier = base_id;
          get_unstuffed_bit(b); // r0
        end else begin
          // EFF: identifier is 29 bits
          tr.identifier[28:18] = base_id;
          // tr.rtr was actually SRR, we'll overwrite it later with real RTR
          
          for (int i = 17; i >= 0; i--) begin
            get_unstuffed_bit(b);
            tr.identifier[i] = b;
          end
          
          get_unstuffed_bit(b); tr.rtr = b; // Actual RTR for EFF
          get_unstuffed_bit(b); // r1
          get_unstuffed_bit(b); // r0
        end
      end

      // 4. DLC (4 bits)
      for (int i = 3; i >= 0; i--) begin
        get_unstuffed_bit(b);
        tr.dlc[i] = b;
      end

      // 5. Data Bytes
      // NOTE: Monitor MUST skip payload mapping on RTR=1 to correctly reach the CRC.
      // We verify the actual physical length of the bitstream later to prove 0 payload bits.
      if (tr.dlc > 8) tr.dlc = 8;
      if (!tr.rtr) begin
        for (int i = 0; i < tr.dlc; i++) begin
          bit [7:0] data_byte;
          for (int j = 7; j >= 0; j--) begin
            get_unstuffed_bit(b);
            data_byte[j] = b;
          end
          tr.data[i] = data_byte;
        end
      end

      // 6. CRC (15 bits)
      for (int i = 0; i < 15; i++) get_unstuffed_bit(b);
      
      // Pass the entire parsed, unstuffed bitstream to the Scoreboard for deep inspection
      tr.unstuffed_bits = unstuffed_bits;
      
      // Capture the exact number of unstuffed physical bits from SOF to end of CRC
      tr.unstuffed_bits_length = unstuffed_bits.size();

      // Protocol Check: If we end the CRC on a stuff-bit boundary, 
      // there is one more stuff bit to discard before the non-stuffed region.
      if (same_bit_count == 5) begin
        bit stuff_b;
        get_raw_bit(stuff_b);
        stuff_bits_count++;
      end

      // 7. Non-stuffed region (Fixed polarity)
      get_raw_bit(b); // CRC Delimiter (1)
      get_raw_bit(b); // ACK Slot (0=captured)
      get_raw_bit(b); // ACK Delimiter (1)

      // 8. EOF (7 bits of 1s)
      repeat(7) get_raw_bit(b);

      // -- Final Verification Report --
      begin
        string raw_bin_str = "";
        foreach (raw_bits[i]) raw_bin_str = {raw_bin_str, $sformatf("%b", raw_bits[i])};

        `uvm_info("CB_VERIF", "--------------------------------------------------", UVM_LOW)
        `uvm_info("CB_VERIF", $sformatf("frame recieved (raw binary): %s", raw_bin_str), UVM_DEBUG)
        `uvm_info("CB_VERIF", $sformatf("total stuff bits removed   : %0d", stuff_bits_count), UVM_HIGH)
        if (tr.ide == 0) begin
          if (tr.rtr == 1)
            `uvm_info("CB_VERIF", $sformatf("decoded frame (SFF REMOTE): ID=0x%03h RTR=%0b DLC=%0d (Bitstream Length=%0d bits)", tr.identifier[10:0], tr.rtr, tr.dlc, tr.unstuffed_bits_length), UVM_LOW)
          else
            `uvm_info("CB_VERIF", $sformatf("decoded frame (SFF DATA)  : ID=0x%03h RTR=%0b DLC=%0d Data=[0x%02h 0x%02h 0x%02h 0x%02h 0x%02h 0x%02h 0x%02h 0x%02h]", 
              tr.identifier[10:0], tr.rtr, tr.dlc, tr.data[0], tr.data[1], tr.data[2], tr.data[3], tr.data[4], tr.data[5], tr.data[6], tr.data[7]), UVM_LOW)
        end else begin
          if (tr.rtr == 1)
            `uvm_info("CB_VERIF", $sformatf("decoded frame (EFF REMOTE): ID=0x%08h RTR=%0b DLC=%0d (Bitstream Length=%0d bits)", tr.identifier, tr.rtr, tr.dlc, tr.unstuffed_bits_length), UVM_LOW)
          else
            `uvm_info("CB_VERIF", $sformatf("decoded frame (EFF DATA)  : ID=0x%08h RTR=%0b DLC=%0d Data=[0x%02h 0x%02h 0x%02h 0x%02h 0x%02h 0x%02h 0x%02h 0x%02h]", 
              tr.identifier, tr.rtr, tr.dlc, tr.data[0], tr.data[1], tr.data[2], tr.data[3], tr.data[4], tr.data[5], tr.data[6], tr.data[7]), UVM_LOW)
        end
        `uvm_info("CB_VERIF", "--------------------------------------------------", UVM_LOW)
      end

      item_collected_port.write(tr);

      // Wait for Intermission / Bus Idle
      repeat(3) get_raw_bit(b);
      wait(vif.can_tx == 1); 
      #200ns;
    end
  endtask
endclass
