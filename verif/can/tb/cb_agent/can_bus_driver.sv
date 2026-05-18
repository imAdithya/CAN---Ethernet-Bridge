class can_bus_driver extends uvm_driver #(cb_trans_debug);
  `uvm_component_utils(can_bus_driver)
  can_vif vif;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    vif = can_bus_pkg::static_vif;
  endfunction

  // ------------------------------------------------------------------
  // CRC-15 Calculation (Standard CAN Polynomial: 0x4599)
  // ------------------------------------------------------------------
  function bit [14:0] calculate_crc(bit bits[]);
    bit [14:0] crc = 0;
    foreach (bits[i]) begin
      bit inv = bits[i] ^ crc[14];
      crc = {crc[13:0], 1'b0};
      if (inv) crc = crc ^ 15'h4599;
    end
    return crc;
  endfunction

  // ------------------------------------------------------------------
  // Driver Run Phase
  // ------------------------------------------------------------------
  virtual task run_phase(uvm_phase phase);
    cb_trans_debug tr;
    
    // Default state: Recessive
    vif.can_rx = 1;
    
    wait(vif.rst === 0);
    
    forever begin
      seq_item_port.get_next_item(tr);
      `uvm_info("CAN_DRV", $sformatf("Driving RX frame: ID=0x%h DLC=%0d", tr.identifier, tr.dlc), UVM_LOW)
      drive_frame(tr);
      seq_item_port.item_done();
    end
  endtask

  // ------------------------------------------------------------------
  // Core Driving Logic
  // ------------------------------------------------------------------
  task drive_frame(cb_trans_debug tr);
    bit bits_to_stuff[];
    bit bits_on_wire[];
    bit [14:0] crc;
    
    // 0. Pre-frame Idle (Ensure DUT sees transition if it just came out of reset)
    repeat(15) begin
      vif.can_rx = 1;
      repeat(vif.bit_time_clks) @(posedge vif.clk);
    end

    // 1. Serialize message (SOF to DLC)
    // SOF (0)
    bits_to_stuff = {bits_to_stuff, 1'b0};
    
    if (tr.ide == 0) begin
      // SFF
      for (int i=10; i>=0; i--) bits_to_stuff = {bits_to_stuff, tr.identifier[i]};
      bits_to_stuff = {bits_to_stuff, tr.rtr};
      bits_to_stuff = {bits_to_stuff, 1'b0}; // IDE=0
      bits_to_stuff = {bits_to_stuff, 1'b0}; // r0
    end else begin
      // EFF
      for (int i=28; i>=18; i--) bits_to_stuff = {bits_to_stuff, tr.identifier[i]};
      bits_to_stuff = {bits_to_stuff, 1'b1}; // SRR=1
      bits_to_stuff = {bits_to_stuff, 1'b1}; // IDE=1
      for (int i=17; i>=0; i--)  bits_to_stuff = {bits_to_stuff, tr.identifier[i]};
      bits_to_stuff = {bits_to_stuff, tr.rtr};
      bits_to_stuff = {bits_to_stuff, 1'b0}; // r1
      bits_to_stuff = {bits_to_stuff, 1'b0}; // r0
    end
    
    // DLC
    for (int i=3; i>=0; i--) bits_to_stuff = {bits_to_stuff, tr.dlc[i]};
    
    // Data (only if not RTR)
    if (!tr.rtr) begin
      for (int i=0; i<tr.dlc; i++) begin
        for (int j=7; j>=0; j--) bits_to_stuff = {bits_to_stuff, tr.data[i][j]};
      end
    end
    
    // Calculate CRC (on unstuffed SOF..Data bits)
    crc = calculate_crc(bits_to_stuff);
    for (int i=14; i>=0; i--) bits_to_stuff = {bits_to_stuff, crc[i]};
    
    // 2. Apply Bit Stuffing
    begin
      int count = 0;
      bit last_bit = bits_to_stuff[0];
      bits_on_wire = {bits_on_wire, last_bit};
      count = 1;
      
      for (int i=1; i<bits_to_stuff.size(); i++) begin
        if (bits_to_stuff[i] == last_bit) begin
          count++;
          if (count == 5) begin
            bits_on_wire = {bits_on_wire, bits_to_stuff[i]};
            bits_on_wire = {bits_on_wire, !bits_to_stuff[i]}; // Stuff bit
            last_bit = !bits_to_stuff[i];
            count = 1;
          end else begin
            bits_on_wire = {bits_on_wire, bits_to_stuff[i]};
          end
        end else begin
          bits_on_wire = {bits_on_wire, bits_to_stuff[i]};
          last_bit = bits_to_stuff[i];
          count = 1;
        end
      end
    end
    
    // 3. Add Fixed Polarity bits (No stuffing)
    bits_on_wire = {bits_on_wire, 1'b1}; // CRC Delimiter
    bits_on_wire = {bits_on_wire, 1'b1}; // ACK Slot (Driver drives recessive)
    bits_on_wire = {bits_on_wire, 1'b1}; // ACK Delimiter
    for (int i=0; i<7; i++)  bits_on_wire = {bits_on_wire, 1'b1}; // EOF
    for (int i=0; i<3; i++)  bits_on_wire = {bits_on_wire, 1'b1}; // Intermission
    
    // 4. Drive on wire
    foreach (bits_on_wire[i]) begin
      vif.can_rx = bits_on_wire[i];
      repeat(vif.bit_time_clks) @(posedge vif.clk);
    end
    
    // Back to idle
    vif.can_rx = 1;
    repeat(10) @(posedge vif.clk);
  endtask

endclass
