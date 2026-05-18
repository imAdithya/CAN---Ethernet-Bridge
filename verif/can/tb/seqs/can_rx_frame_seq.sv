class can_rx_frame_seq extends uvm_sequence#(cb_trans_debug);
  `uvm_object_utils(can_rx_frame_seq)

  rand bit        ide;
  rand bit        rtr;
  rand bit [28:0] id;
  rand bit [3:0]  dlc;
  rand bit [7:0]  data[8];

  function new(string name = "can_rx_frame_seq");
    super.new(name);
  endfunction

  virtual task body();
    cb_trans_debug tr;
    tr = cb_trans_debug::type_id::create("tr");
    start_item(tr);
    tr.ide        = ide;
    tr.rtr        = rtr;
    tr.identifier = id;
    tr.dlc        = dlc;
    foreach (data[i]) tr.data[i] = data[i];
    finish_item(tr);
  endtask
endclass
