class dma_sequencer extends uvm_sequencer #(wishbone_transaction);
  `uvm_component_utils(dma_sequencer)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction
endclass
