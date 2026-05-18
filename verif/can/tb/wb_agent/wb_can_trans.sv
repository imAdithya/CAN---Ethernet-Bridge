class wb_can_trans extends uvm_sequence_item;
  // SJA1000 uses 8-bit addressing and 8-bit data 
  rand logic [7:0] addr; 
  rand logic [7:0] data;
  rand logic       we;   // Write enable: 1 for Write, 0 for Read 
  
  // Selection bits for byte lanes (typically 4'h1 for 8-bit bus) 
  rand logic [3:0] sel;

  `uvm_object_utils_begin(wb_can_trans)
    `uvm_field_int(addr, UVM_ALL_ON)
    `uvm_field_int(data, UVM_ALL_ON)
    `uvm_field_int(sel,  UVM_ALL_ON)
    `uvm_field_int(we,   UVM_ALL_ON)
  `uvm_object_utils_end

  function new(string name = "wb_can_trans");
    super.new(name); 
  endfunction

  // Constraint to keep addresses within the SJA1000 register map (0x0 to 0x1F)
  constraint sja1000_range { addr inside {[8'h0 : 8'h1F]}; }
  constraint default_sel   { sel == 4'h1; }
  
endclass