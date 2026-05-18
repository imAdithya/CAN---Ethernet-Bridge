// can_wb_agent_config.sv
class can_wb_agent_config extends uvm_object;
  `uvm_object_utils(can_wb_agent_config)

  virtual can_wb_if vif;
  uvm_active_passive_enum is_active = UVM_ACTIVE;

  // Pre-loaded CAN register file (simulates SJA1000 registers)
  // Sequences write here before asserting can_rx_irq
  bit [7:0] can_regs[32];

  function new(string name = "can_wb_agent_config");
    super.new(name);
    foreach (can_regs[i]) can_regs[i] = 8'h00;
  endfunction

  // Helper: load a CAN frame into the register file
  function void load_can_frame(
    bit [28:0] can_id, bit [3:0] dlc,
    bit eff, bit rtr, bit [7:0] data[8]
  );
    // Register 0x10: frame info {eff, rtr, 2'b0, dlc}
    can_regs['h10] = {eff, rtr, 2'b0, dlc};
    // Registers 0x11-0x14: ID bytes (MSB first)
    can_regs['h11] = can_id[28:21];
    can_regs['h12] = can_id[20:13];
    can_regs['h13] = can_id[12:5];
    can_regs['h14] = {can_id[4:0], 3'b0};
    // Registers 0x15-0x1C: data bytes
    for (int i = 0; i < 8; i++)
      can_regs['h15 + i] = data[i];
  endfunction
endclass
