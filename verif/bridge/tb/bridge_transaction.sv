// bridge_transaction.sv — Transaction classes for the bridge TB


// =========================================================================
// CAN Frame Transaction — represents a CAN 2.0 frame
// =========================================================================
class can_frame_transaction extends uvm_sequence_item;
  `uvm_object_utils(can_frame_transaction)

  rand bit [28:0] can_id;
  rand bit [3:0]  dlc;
  rand bit        eff;       // Extended Frame Format (29-bit ID)
  rand bit        rtr;       // Remote Transmit Request
  rand bit [7:0]  data[8];   // Up to 8 bytes

  // Direction metadata
  bit is_upstream;   // 1 = CAN→ETH, 0 = ETH→CAN

  constraint c_dlc { dlc inside {[0:8]}; }
  constraint c_std_id { !eff -> can_id[28:11] == 0; }  // 11-bit if standard

  function new(string name = "can_frame_transaction");
    super.new(name);
  endfunction

  function void do_copy(uvm_object rhs);
    can_frame_transaction rhs_;
    if (!$cast(rhs_, rhs))
      `uvm_fatal("COPY", "Type mismatch in can_frame_transaction")
    this.can_id      = rhs_.can_id;
    this.dlc         = rhs_.dlc;
    this.eff         = rhs_.eff;
    this.rtr         = rhs_.rtr;
    this.data        = rhs_.data;
    this.is_upstream = rhs_.is_upstream;
  endfunction

  function string convert2string();
    return $sformatf("CAN: ID=0x%0h DLC=%0d EFF=%0b RTR=%0b Data=%0h%0h%0h%0h%0h%0h%0h%0h %s",
      can_id, dlc, eff, rtr,
      data[0], data[1], data[2], data[3],
      data[4], data[5], data[6], data[7],
      is_upstream ? "[UP]" : "[DN]");
  endfunction
endclass : can_frame_transaction

// =========================================================================
// Bridge WB Transaction — for CAN/MEM bus monitoring
// =========================================================================
class bridge_wb_transaction extends uvm_sequence_item;
  `uvm_object_utils(bridge_wb_transaction)

  bit [31:0] address;
  bit [31:0] write_data;
  bit [31:0] read_data;
  bit        is_read;
  bit [3:0]  sel;
  bit        is_can_bus;   // 1 = CAN bus, 0 = ETH/MEM bus

  function new(string name = "bridge_wb_transaction");
    super.new(name);
  endfunction

  function string convert2string();
    return $sformatf("BridgeWB: %s Addr=0x%0h %s=0x%0h [%s]",
      is_read ? "RD" : "WR", address,
      is_read ? "RData" : "WData",
      is_read ? read_data : write_data,
      is_can_bus ? "CAN" : "MEM");
  endfunction
endclass : bridge_wb_transaction
