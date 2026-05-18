// CAN RX Base Test - Contains common helper methods
class can_rx_base_test extends uvm_test;
  `uvm_component_utils(can_rx_base_test)
  wb_can_env env;
  can_bus_pkg::can_bus_agent can_agt;
  can_rx_frame_seq rx_seq;

  function new(string name = "can_rx_base_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = wb_can_env::type_id::create("env", this);
    uvm_config_db#(uvm_active_passive_enum)::set(this, "can_agt", "is_active", UVM_ACTIVE);
    can_agt = can_bus_pkg::can_bus_agent::type_id::create("can_agt", this);
    rx_seq = can_rx_frame_seq::type_id::create("rx_seq");
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    can_agt.monitor.item_collected_port.connect(env.scb.can_export);
  endfunction

  task write_reg(bit [7:0] addr, bit [7:0] data);
    wb_can_trans req = wb_can_trans::type_id::create("req");
    req.addr = addr; req.we = 1; req.data = data;
    env.agt.sequencer.execute_item(req);
  endtask

  task read_reg(bit [7:0] addr, output bit [7:0] data);
    wb_can_trans req = wb_can_trans::type_id::create("req");
    req.addr = addr; req.we = 0;
    env.agt.sequencer.execute_item(req);
    data = req.data;
  endtask

  task check_rx_fifo(int expected_dlc = 0, bit [7:0] expected_data[] = {});
    bit [7:0] status, rx_info, data_byte, irq;
    
    // Check IRQ register (0x03) - Bit 0 is Receive Interrupt
    read_reg(8'h03, irq);
    if (irq[0]) `uvm_info("RX_BASE", "Receive Interrupt (RI) detected!", UVM_MEDIUM)

    // Read Status Reg (0x02) - Bit 0 is Receive Buffer Status
    read_reg(8'h02, status);
    if (status[0] == 1) begin
      `uvm_info("RX_BASE", "Frame successfully received in FIFO!", UVM_LOW)
      // Read Frame Info (0x10)
      read_reg(8'h10, rx_info);
      if (rx_info[3:0] !== expected_dlc[3:0])
        `uvm_error("RX_FAIL", $sformatf("DLC mismatch! Exp: %0d, Got: %0d", expected_dlc, rx_info[3:0]))
      
      // Read Data
      for (int i=0; i<expected_dlc; i++) begin
        read_reg(8'h13 + i, data_byte);
        if (data_byte !== expected_data[i])
          `uvm_error("RX_FAIL", $sformatf("Data[%0d] mismatch! Exp: 0x%h, Got: 0x%h", i, expected_data[i], data_byte))
        else
          `uvm_info("RX_BASE", $sformatf("Data[%0d] match: 0x%h", i, data_byte), UVM_HIGH)
      end
      
      // Release Buffer (CMR.2=1)
      write_reg(8'h01, 8'h04);
    end else begin
      `uvm_error("RX_FAIL", "RX FIFO EMPTY!")
    end
  endtask
endclass
