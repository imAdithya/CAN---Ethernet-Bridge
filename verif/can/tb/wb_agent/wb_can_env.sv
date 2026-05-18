class wb_can_env extends uvm_env;
  `uvm_component_utils(wb_can_env)

  wb_can_agent      agt;
  wb_can_scoreboard scb;
  wb_can_coverage   cov;
  can_tx_coverage   tx_cov;
  can_rx_coverage   rx_cov;
  can_prot_coverage prot_cov;
  can_err_coverage  err_cov;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    agt = wb_can_agent::type_id::create("agt", this);
    scb = wb_can_scoreboard::type_id::create("scb", this);
    cov = wb_can_coverage::type_id::create("cov", this);
    tx_cov = can_tx_coverage::type_id::create("tx_cov", this);
    rx_cov = can_rx_coverage::type_id::create("rx_cov", this);
    prot_cov = can_prot_coverage::type_id::create("prot_cov", this);
    err_cov = can_err_coverage::type_id::create("err_cov", this);
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);

    agt.monitor.ap.connect(scb.wb_export);
    agt.monitor.ap.connect(cov.analysis_export);
    agt.monitor.ap.connect(tx_cov.wb_export);
    agt.monitor.ap.connect(rx_cov.wb_export);
    agt.monitor.ap.connect(prot_cov.wb_export);
    agt.monitor.ap.connect(err_cov.wb_export);
    
    // Note: The CAN agent is instantiated in the TEST (can_tx_sff_test.sv)
    // We will handle the CAN connection in the test's connect_phase
  endfunction
endclass