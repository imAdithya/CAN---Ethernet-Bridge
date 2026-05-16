// mem_wb_driver.sv — WB slave responder for shared RAM + ETH MAC BDs
// Responds to bridge's ETH master reads/writes

class mem_wb_driver extends uvm_driver;
  `uvm_component_utils(mem_wb_driver)

  virtual mem_wb_if.Slave vif;
  mem_wb_agent_config cfg;

  function new(string name = "mem_wb_driver", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(mem_wb_agent_config)::get(this, "", "config", cfg))
      `uvm_fatal("CFG", "Cannot get mem_wb_agent_config")
    vif = cfg.vif;
  endfunction

  task run_phase(uvm_phase phase);
    vif.dat_s = 32'h0;
    vif.ack   = 1'b0;

    forever begin
      @(posedge vif.clk iff (vif.cyc && vif.stb));

      if (vif.we) begin
        // WRITE: bridge storing frame data or programming BD
        cfg.memory[vif.adr >> 2] = apply_sel(cfg.memory[vif.adr >> 2],
                                              vif.dat_m, vif.sel);
        `uvm_info("MEM_DRV", $sformatf("WR [0x%08h] = 0x%08h sel=%04b",
                  vif.adr, vif.dat_m, vif.sel), UVM_HIGH)
      end else begin
        // READ: bridge reading BD status or frame data
        vif.dat_s = cfg.memory[vif.adr >> 2];
        `uvm_info("MEM_DRV", $sformatf("RD [0x%08h] = 0x%08h",
                  vif.adr, cfg.memory[vif.adr >> 2]), UVM_HIGH)
      end

      vif.ack = 1'b1;
      @(posedge vif.clk);
      vif.ack = 1'b0;
    end
  endtask

  // Apply byte enables to write data
  function bit [31:0] apply_sel(bit [31:0] old_val, bit [31:0] new_val,
                                 bit [3:0] sel);
    bit [31:0] result = old_val;
    if (sel[3]) result[31:24] = new_val[31:24];
    if (sel[2]) result[23:16] = new_val[23:16];
    if (sel[1]) result[15:8]  = new_val[15:8];
    if (sel[0]) result[7:0]   = new_val[7:0];
    return result;
  endfunction
endclass
