// mem_wb_agent_config.sv
class mem_wb_agent_config extends uvm_object;
  `uvm_object_utils(mem_wb_agent_config)

  virtual mem_wb_if vif;
  uvm_active_passive_enum is_active = UVM_ACTIVE;

  // Simulated memory (4KB address space: BDs + frame data)
  bit [31:0] memory[4096];   // Word-addressed: memory[addr>>2]

  function new(string name = "mem_wb_agent_config");
    super.new(name);
    foreach (memory[i]) memory[i] = 32'h0;
  endfunction

  // Helper: load an Ethernet frame into memory at a given base address
  function void load_eth_frame(bit [31:0] base_addr, bit [31:0] frame_words[],
                                int num_words);
    for (int i = 0; i < num_words; i++)
      memory[(base_addr >> 2) + i] = frame_words[i];
  endfunction

  // Helper: setup RX BD pointing to frame data
  function void setup_rx_bd(bit [31:0] bd_addr, bit [31:0] frame_ptr,
                             bit [15:0] length);
    memory[bd_addr >> 2]       = {length, 16'h0000};  // Status: not empty
    memory[(bd_addr >> 2) + 1] = frame_ptr;            // Pointer
  endfunction
endclass
