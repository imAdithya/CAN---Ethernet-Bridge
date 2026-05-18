`timescale 1ns/10ps

// CAN Bus Agent
class can_bus_agent extends uvm_agent;
  `uvm_component_utils(can_bus_agent)

  can_bus_sequencer sequencer;
  can_bus_driver    driver;
  can_bus_monitor   monitor;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    monitor = can_bus_monitor::type_id::create("monitor", this);
    if (get_is_active() == UVM_ACTIVE) begin
      sequencer = can_bus_sequencer::type_id::create("sequencer", this);
      driver    = can_bus_driver::type_id::create("driver", this);
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    if (get_is_active() == UVM_ACTIVE) begin
      driver.seq_item_port.connect(sequencer.seq_item_export);
    end
  endfunction
endclass
