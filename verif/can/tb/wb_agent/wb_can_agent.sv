class wb_can_agent extends uvm_agent;
  `uvm_component_utils(wb_can_agent)

  wb_can_driver    driver;
  wb_can_sequencer sequencer;
  wb_can_monitor   monitor;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    driver    = wb_can_driver::type_id::create("driver", this);
    sequencer = wb_can_sequencer::type_id::create("sequencer", this);
    monitor   = wb_can_monitor::type_id::create("monitor", this);
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    driver.seq_item_port.connect(sequencer.seq_item_export);
  endfunction
endclass