// TX-04: Data Length Code (DLC) Variation Sequence
// Configures DUT in PeliCAN mode and transmits frames with randomized DLC
// values from 0 to 8, ensuring exactly `DLC` number of bytes are transmitted.

class can_tx_dlc_rand_seq extends uvm_sequence#(wb_can_trans);
  `uvm_object_utils(can_tx_dlc_rand_seq)

  function new(string name = "can_tx_dlc_rand_seq");
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
    end
  endtask

  // Transmit a specific DLC length frame with randomized data
  task transmit_random_dlc();
    bit [10:0] can_id;
    bit [3:0]  dlc;
    bit [7:0]  frame_info, id1, id2;
    bit [7:0]  payload[8];

    // Seed variables
    std::randomize(can_id);
    std::randomize(dlc) with { dlc <= 8; };
    for (int i=0; i<8; i++) std::randomize(payload[i]);

    // SJA1000 PeliCAN SFF: 0x10.7 = FF(0), 0x10.6 = RTR(0)
    frame_info = {1'b0, 1'b0, 2'b00, dlc};
    id1 = can_id[10:3];
    id2 = {can_id[2:0], 5'b00000};

    `uvm_info("TX_DLC", $sformatf("Loading DLC=%0d Random SFF Frame (ID=0x%03h)", dlc, can_id), UVM_LOW)

    // Write Header
    wb_write(8'h10, frame_info);
    wb_write(8'h11, id1);
    wb_write(8'h12, id2);

    // Write Variable Payload Payload
    for (int i = 0; i < dlc; i++) begin
      wb_write(8'h13 + i, payload[i]);
    end

    // Trigger TX
    wb_write(8'h01, 8'h10); // Self-TX Command
    wait_tx_complete();
  endtask

  virtual task body();
    `uvm_info(get_name(), "=== TX-04: DLC VARIATION TEST START ===", UVM_LOW)

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

    // Phase 2: Transmit 50 Random Frames to cover all DLC bins (0-8)
    for (int iter = 0; iter < 50; iter++) begin
      transmit_random_dlc();
      #2000; // brief gap between frames
    end

    `uvm_info(get_name(), "=== TX-04: DLC TEST COMPLETE ===", UVM_LOW)
  endtask
endclass
