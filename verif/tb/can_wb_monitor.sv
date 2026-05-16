// can_wb_monitor.sv — Monitors CAN WB bus transactions
// Reconstructs CAN frames from byte-level register reads/writes

class can_wb_monitor extends uvm_monitor;
  `uvm_component_utils(can_wb_monitor)

  virtual can_wb_if.Monitor vif;
  can_wb_agent_config cfg;

  uvm_analysis_port #(bridge_wb_transaction) item_collected_port;
  uvm_analysis_port #(can_frame_transaction) can_frame_port;

  // Accumulate CAN frame from individual register accesses
  bit [7:0] captured_regs[32];
  int       reg_count;
  bit       capturing_read;   // true during upstream read sequence
  bit       capturing_write;  // true during downstream write sequence

  function new(string name = "can_wb_monitor", uvm_component parent = null);
    super.new(name, parent);
    item_collected_port = new("item_collected_port", this);
    can_frame_port      = new("can_frame_port", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(can_wb_agent_config)::get(this, "", "config", cfg))
      `uvm_fatal("CFG", "Cannot get can_wb_agent_config")
    vif = cfg.vif;
  endfunction

  task run_phase(uvm_phase phase);
    bridge_wb_transaction txn;
    reg_count = 0;
    capturing_read = 0;
    capturing_write = 0;

    forever begin
      @(posedge vif.clk iff (vif.cyc && vif.stb && vif.ack));

      // Create WB transaction
      txn = bridge_wb_transaction::type_id::create("can_wb_txn");
      txn.address    = {24'h0, vif.adr};
      txn.is_read    = !vif.we;
      txn.write_data = {24'h0, vif.dat_m};
      txn.read_data  = {24'h0, vif.dat_s};
      txn.is_can_bus = 1;
      item_collected_port.write(txn);

      // Track register accesses to reconstruct CAN frames
      if (!vif.we && vif.adr >= 8'h10 && vif.adr <= 8'h1C) begin
        // Bridge reading CAN RX registers (upstream)
        captured_regs[vif.adr[4:0]] = vif.dat_s;
        capturing_read = 1;
        if (vif.adr == 8'h1C) begin
          // Last data byte read — emit complete CAN frame
          emit_can_frame(1);  // upstream
          capturing_read = 0;
        end
      end

      if (vif.we && vif.adr >= 8'h10 && vif.adr <= 8'h1C) begin
        // Bridge writing CAN TX registers (downstream)
        captured_regs[vif.adr[4:0]] = vif.dat_m;
        capturing_write = 1;
        if (vif.adr == 8'h1C) begin
          emit_can_frame(0);  // downstream
          capturing_write = 0;
        end
      end
    end
  endtask

  // Reconstruct CAN frame from captured register bytes
  function void emit_can_frame(bit is_upstream);
    can_frame_transaction frame = can_frame_transaction::type_id::create("can_frame");
    frame.eff   = captured_regs['h10][7];
    frame.rtr   = captured_regs['h10][6];
    frame.dlc   = captured_regs['h10][3:0];
    frame.can_id = {captured_regs['h11],
                    captured_regs['h12],
                    captured_regs['h13],
                    captured_regs['h14][7:3]};
    for (int i = 0; i < 8; i++)
      frame.data[i] = captured_regs['h15 + i];
    frame.is_upstream = is_upstream;

    `uvm_info("CAN_MON", $sformatf("Frame: %s", frame.convert2string()), UVM_MEDIUM)
    can_frame_port.write(frame);
  endfunction
endclass
