// can_wb_driver.sv — WB slave responder for CAN controller
// Responds to bridge's CAN master reads/writes with register file data

class can_wb_driver extends uvm_driver;
  `uvm_component_utils(can_wb_driver)

  virtual can_wb_if.Slave vif;
  can_wb_agent_config cfg;

  // Local register file mirror
  bit [7:0] regs[32];

  function new(string name = "can_wb_driver", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(can_wb_agent_config)::get(this, "", "config", cfg))
      `uvm_fatal("CFG", "Cannot get can_wb_agent_config")
    vif = cfg.vif;
  endfunction

  task run_phase(uvm_phase phase);
    // Initialize outputs
    vif.dat_s = 8'h00;
    vif.ack   = 1'b0;

    forever begin
      @(posedge vif.cyc);  // Wait for bus cycle start

      while (vif.cyc) begin
        @(posedge vif.clk iff (vif.cyc && vif.stb));

        // Copy latest register file from config (sequences may update it)
        regs = cfg.can_regs;

        if (vif.we) begin
          // WRITE: bridge writing to CAN controller (downstream TX or cmd)
          regs[vif.adr[4:0]] = vif.dat_m;
          cfg.can_regs[vif.adr[4:0]] = vif.dat_m;
          `uvm_info("CAN_DRV", $sformatf("WR [0x%02h] = 0x%02h", vif.adr, vif.dat_m), UVM_HIGH)
        end else begin
          // READ: bridge reading CAN registers (upstream RX)
          vif.dat_s = regs[vif.adr[4:0]];
          `uvm_info("CAN_DRV", $sformatf("RD [0x%02h] = 0x%02h", vif.adr, regs[vif.adr[4:0]]), UVM_HIGH)
        end

        // Assert ACK for one cycle
        vif.ack = 1'b1;
        @(posedge vif.clk);
        vif.ack = 1'b0;
      end
    end
  endtask
endclass
