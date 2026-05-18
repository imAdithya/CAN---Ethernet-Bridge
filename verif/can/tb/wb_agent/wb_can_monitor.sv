class wb_can_monitor extends uvm_monitor;
  `uvm_component_utils(wb_can_monitor)

  virtual wb_can_if vif;
  uvm_analysis_port #(wb_can_trans) ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual wb_can_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "Virtual interface not found for wb_can_monitor")
  endfunction

  virtual task run_phase(uvm_phase phase);
    forever begin
      wb_can_trans tx;
      // Use direct signal access (not clocking block) for monitor observation
      // to avoid vsim-8441 warnings about reading clocking block outputs
      @(posedge vif.clk);
      if (vif.stb && vif.cyc && vif.ack) begin
        tx = wb_can_trans::type_id::create("tx");
        tx.addr = vif.adr;
        tx.we   = vif.we;
        tx.data = (tx.we) ? vif.din : vif.dout;
        tx.sel  = vif.sel;
        ap.write(tx);
      end
    end
  endtask
endclass