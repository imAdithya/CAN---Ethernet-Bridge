// RX-08: RTR Receive Handling
class can_rx_rtr_test extends can_rx_base_test;
  `uvm_component_utils(can_rx_rtr_test)

  function new(string name = "can_rx_rtr_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    #300ns;
    
    `uvm_info("TEST", "Starting RX-08: RTR Receive Handling Test", UVM_LOW)

    // 1. Configure DUT: PeliCAN, Accept everything
    write_reg(8'h1F, 8'h80);  // CDR.7=1 (PeliCAN mode)
    write_reg(8'h00, 8'h09);  // MOD.0=1 (Reset Mode), MOD.3=1 (Single Filter)
    // BTR0, BTR1
    write_reg(8'h06, 8'h00);
    write_reg(8'h07, 8'h25);
    // AMR0-3 = 0xFF: Accept ALL frames
    write_reg(8'h14, 8'hFF);
    write_reg(8'h15, 8'hFF);
    write_reg(8'h16, 8'hFF);
    write_reg(8'h17, 8'hFF);
    write_reg(8'h00, 8'h08);  // Exit Reset, stay in Single Filter mode
    #1000ns;

    // 2. Inject RTR Frame (ID=0x333, DLC=8)
    // Even if DLC=8, RTR frames have no data payload bitstream.
    `uvm_info("TEST", "Injecting SFF RTR Frame (ID=0x333, DLC=8)...", UVM_LOW)
    rx_seq.ide = 0;
    rx_seq.rtr = 1;
    rx_seq.id = 29'h333; rx_seq.dlc = 8;
    rx_seq.start(can_agt.sequencer);
    #200us;

    // 3. Verify FIFO content
    begin
      bit [7:0] rx_info, status;
      read_reg(8'h02, status);
      if (status[0]) begin
        read_reg(8'h10, rx_info);
        // Bit 6 of Frame Info is RTR. Should be 1. DLC should be 8.
        if (rx_info[6] == 1 && rx_info[3:0] == 4'd8)
          `uvm_info("TEST", $sformatf("RTR Frame correctly received and identified in FIFO. Info=0x%h", rx_info), UVM_LOW)
        else
          `uvm_error("TEST", $sformatf("RTR Frame Info mismatch! Expected RTR=1,DLC=8, Got Info=0x%h", rx_info))
      end else begin
        `uvm_error("TEST", "RX FIFO EMPTY after RTR injection!")
      end
    end

    `uvm_info("TEST", "RX-08: TEST COMPLETE", UVM_LOW)
    phase.drop_objection(this);
  endtask
endclass
