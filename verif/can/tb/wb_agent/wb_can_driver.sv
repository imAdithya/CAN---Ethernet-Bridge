class wb_can_driver extends uvm_driver #(wb_can_trans);
  `uvm_component_utils(wb_can_driver)

  virtual wb_can_if vif;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual wb_can_if)::get(this, "", "vif", vif))
      `uvm_fatal("DRV", "Could not get virtual interface")
  endfunction

  virtual task run_phase(uvm_phase phase);
    vif.cb.stb <= 0;
    vif.cb.cyc <= 0;
    
    forever begin
      seq_item_port.get_next_item(req);
      drive_tx(req);
      seq_item_port.item_done();
    end
  endtask

  virtual task drive_tx(wb_can_trans tx);
    @(vif.cb);
    vif.cb.adr <= tx.addr;
    vif.cb.we  <= tx.we;
    vif.cb.sel <= tx.sel;
    vif.cb.cyc <= 1;
    vif.cb.stb <= 1;
    if (tx.we) vif.cb.din <= tx.data;

    // Wait for the 3-cycle ACK handshake from SJA1000
    do begin
      @(vif.cb);
    end while (vif.cb.ack !== 1);

    if (!tx.we) tx.data = vif.cb.dout;

    vif.cb.cyc <= 0;
    vif.cb.stb <= 0;

    // Wait 6 idle cycles for CDC reset path (cs_sync_rst) to complete
    // before allowing the next Wishbone transaction
    repeat(6) @(vif.cb);
  endtask
endclass