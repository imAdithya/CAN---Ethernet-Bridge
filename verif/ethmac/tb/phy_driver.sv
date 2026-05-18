// tb/uvm_components/phy_agent/phy_driver.sv
`include "uvm_macros.svh"
import uvm_pkg::*;

class phy_driver extends uvm_driver#(ethernet_frame_transaction);
  `uvm_component_utils(phy_driver)

  // Virtual interface handle
  // At top of class
  virtual mii_if vif;
  phy_agent_config m_config;
  
  // Internal PHY registers
  reg [15:0] phy_regs[32];

  function new(string name = "phy_driver", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(phy_agent_config)::get(this, "", "config", m_config))
      `uvm_fatal("CONFIG_LOAD", "Cannot get config object for phy_driver")

    `uvm_info("PHY_DRIVER",
          $sformatf("PHY CONFIG collisions_remaining = %0d",
                    m_config.collisions_remaining),
          UVM_HIGH);


    vif = m_config.vif;
  endfunction : build_phase

  task run_phase(uvm_phase phase);
    // Initialize PHY registers to default values
    initialize_phy_regs();

    vif.col     <= 1'b0;
    vif.crs     <= 1'b0;
    vif.phy_oe  <= 1'b0;  // Disable PHY driving MDIO
    vif.phy_mdo <= 1'b0;

    // [FIX] Initialize RX signals to avoid X-propagation preventing RxEnSync update
    vif.rx_dv   <= 1'b0;
    vif.rxd     <= 4'h0;
    vif.rx_err  <= 1'b0;

    // Fork parallel processes
    fork
      drive_frames();
      handle_miim();
      inject_collision();       // Manual (Event-based)
      auto_collision_handler(); // NEW: Automatic (Counter-based)
      debug_tx_monitor();
      drive_crs_during_tx();
    join
  endtask : run_phase

  // ... (drive_frames and drive_bytes tasks remain the same) ...
  protected virtual task drive_frames();
  forever begin
    seq_item_port.get_next_item(req);

    wait (vif.tx_en === 1'b0);

    `uvm_info("PHY_DRIVER", "Driving RX frame (TX idle)", UVM_MEDIUM)

    // Notify sequence
    m_config.rx_frame_started.trigger();

    // -------------------------------
    // HALF-DUPLEX REQUIREMENT
    // -------------------------------
    // -------------------------------
    // HALF-DUPLEX REQUIREMENT
    // -------------------------------
    vif.crs <= 1'b1;      // Carrier Sense before Data
    vif.col <= 1'b0;
    
    // Wait one cycle 
    @(vif.rx_cb); 

    vif.rx_cb.rx_dv <= 1'b1;
    vif.rx_cb.rxd   <= 4'h5; // Nibble 1 (Preamble)

    // Nibbles 2-14 (Preamble) + Nibble 15 (SFD Lo) = 14 more '5's
    repeat (14) begin
      @(vif.rx_cb) vif.rx_cb.rxd <= 4'h5;
    end

    // Nibble 16 (SFD Hi)
    @(vif.rx_cb) vif.rx_cb.rxd <= 4'hD;

    // Frame fields
    drive_bytes(req.dest_addr);
    drive_bytes(req.src_addr);
    drive_bytes({req.type_len[15:8], req.type_len[7:0]});
    drive_bytes(req.payload);
    // Ethernet CRC is transmitted LSB first (little-endian)
    drive_bytes({req.fcs[7:0], req.fcs[15:8],
                 req.fcs[23:16], req.fcs[31:24]});

    // End of frame
    @(vif.rx_cb);
    vif.rx_cb.rx_dv <= 1'b0;
    vif.rx_cb.rxd   <= 4'h0;

    // Hold CRS for one more RX clock (safe)
    @(vif.rx_cb);
    vif.crs <= 1'b0;

    seq_item_port.item_done();
  end
endtask


  
  protected virtual task drive_bytes(byte unsigned data_q[$]);
    foreach(data_q[i]) begin
        @(vif.rx_cb) vif.rx_cb.rxd <= data_q[i][3:0];
        @(vif.rx_cb) vif.rx_cb.rxd <= data_q[i][7:4];
    end
  endtask
  // ... (end drive_frames) ...


  // -----------------------------------------------------------------------
  // NEW TASK: Automatic Collision Injection for Retries
  // -----------------------------------------------------------------------
// In phy_driver.sv

 task auto_collision_handler();
  forever begin
    // --------------------------------------------------
    // 1. Wait for a NEW transmission attempt
    // --------------------------------------------------
    wait (vif.tx_en === 1'b1);

    `uvm_info("PHY_DRIVER_DEBUG",
      $sformatf("TX attempt detected. Collisions left=%0d",
                m_config.collisions_remaining),
      UVM_HIGH)

    // --------------------------------------------------
    // 2. Inject collision only if retries remain
    // --------------------------------------------------
    if (m_config.collisions_remaining > 0) begin
      `uvm_info("PHY_DRIVER",
        $sformatf("Auto-collision injected. Remaining=%0d",
                  m_config.collisions_remaining),
        UVM_MEDIUM)

      // ------------------------------------------------
      // 3. Wait until safely inside payload
      //    (after preamble + SFD)
      // ------------------------------------------------
      repeat (32) @(posedge vif.tx_clk);

      // ------------------------------------------------
      // 4. Assert collision + carrier sense
      // ------------------------------------------------
      vif.col <= 1'b1;
      vif.crs <= 1'b1;

      // ------------------------------------------------
      // 5. Hold collision (jam sequence)
      // ------------------------------------------------
      repeat (32) @(posedge vif.tx_clk);

      // ------------------------------------------------
      // 6. Deassert collision
      // ------------------------------------------------
      vif.col <= 1'b0;
      vif.crs <= 1'b0;

      // ------------------------------------------------
      // 7. Consume one retry
      // ------------------------------------------------
      m_config.collisions_remaining--;

      // ------------------------------------------------
      // 8. Wait for MAC to abort/backoff
      // ------------------------------------------------
      wait (vif.tx_en === 1'b0);

      // Guard gap before next attempt
      repeat (8) @(posedge vif.tx_clk);
    end
    else begin
      // No collisions left → allow MAC to complete
      wait (vif.tx_en === 1'b0);
    end
  end
endtask


  // ... (handle_miim, initialize_phy_regs, inject_collision remain the same) ...
  // tb/uvm_components/phy_agent/phy_driver.sv

  protected virtual task handle_miim();
     logic [1:0] op_code;
     logic [4:0] phy_addr, reg_addr;
     logic [15:0] data;
     
     // Initialize outputs
     vif.phy_oe  <= 1'b0;
     vif.phy_mdo <= 1'b0;

     forever begin
        // Wait for first start bit: mdio_i goes 0 while mdc is high
        wait(vif.mdc === 1 && vif.mdio_i === 0); 
        @(posedge vif.mdc);
        
        // Check second start bit (must be 1)
        if(vif.mdio_i === 1) begin 
            // FIX: Advance past the second start bit before reading op-code
            @(posedge vif.mdc);
            op_code[1] = vif.mdio_i; 
            @(posedge vif.mdc);
            op_code[0] = vif.mdio_i; 
            @(posedge vif.mdc);
            
            // Read PHY Address (5 bits, MSB first)
            for(int i=4; i>=0; i--) begin 
                phy_addr[i] = vif.mdio_i; 
                @(posedge vif.mdc); 
            end
            
            // Read Register Address (5 bits, MSB first)
            for(int i=4; i>=0; i--) begin 
                reg_addr[i] = vif.mdio_i; 
                @(posedge vif.mdc); 
            end
            
            if(op_code == 2'b10) begin // READ
                if (phy_addr == 5'd1) begin // Only respond to our PHY address
                    // After reg_addr loop, we're at MAC BitCounter=47 (turnaround).
                    // The MAC reads data from BC=48 to 63. We must:
                    //   BC=47: Drive ACK (0) — turnaround bit 2
                    //   BC=48: Drive data[15] (MSB)
                    //   BC=49: Drive data[14]
                    //   ...
                    //   BC=63: Drive data[0] (LSB)
                    data = phy_regs[reg_addr];
                    
                    // We are already at BC=47 — drive ACK immediately
                    vif.phy_oe  <= 1'b1;
                    vif.phy_mdo <= 1'b0; // ACK (0)
                    
                    // Drive 16 data bits from BC=48 to BC=63
                    for(int i=15; i>=0; i--) begin 
                        @(posedge vif.mdc);
                        vif.phy_mdo <= data[i]; 
                    end
                    
                    @(posedge vif.mdc);
                    vif.phy_oe <= 1'b0; // Release bus
                    
                    `uvm_info("PHY_DRIVER_MIIM", $sformatf("READ PHY[%0d] REG[%0d] -> %04h", phy_addr, reg_addr, data), UVM_HIGH)
                end else begin
                    // Non-existent PHY: don't drive bus, wait for frame to finish
                    repeat(18) @(posedge vif.mdc); // TA(1) + 16 data + 1
                    `uvm_info("PHY_DRIVER_MIIM", $sformatf("READ PHY[%0d] — no response (not our addr)", phy_addr), UVM_HIGH)
                end

            end else if (op_code == 2'b01) begin // WRITE
                @(posedge vif.mdc); @(posedge vif.mdc); // Turnaround
                for(int i=15; i>=0; i--) begin 
                    data[i] = vif.mdio_i; 
                    @(posedge vif.mdc); 
                end
                if (phy_addr == 5'd1) begin // Only store for our PHY address
                    phy_regs[reg_addr] = data;
                    `uvm_info("PHY_DRIVER_MIIM", $sformatf("WRITE PHY[%0d] REG[%0d] <- %04h", phy_addr, reg_addr, data), UVM_HIGH)
                end else begin
                    `uvm_info("PHY_DRIVER_MIIM", $sformatf("WRITE PHY[%0d] — ignored (not our addr)", phy_addr), UVM_HIGH)
                end
            end
        end
     end
  endtask 
  
  protected virtual task initialize_phy_regs();
      phy_regs[0] = 16'h2100;
      phy_regs[1] = 16'h782D;
      phy_regs[2] = 16'h0123;
      phy_regs[3] = 16'h4567;
      phy_regs[4] = 16'h01E1;
      `uvm_info("PHY_DRIVER", "Internal PHY registers initialized", UVM_MEDIUM)
  endtask

  task inject_collision();
    forever begin
      m_config.collision_event.wait_trigger();

      `uvm_info("PHY_DRIVER",
        $sformatf("Manual collision ASSERT at %0t", $time),
        UVM_MEDIUM)

      @(posedge vif.tx_clk);
      vif.col <= 1'b1;
      vif.crs <= 1'b1;

      repeat(4) @(posedge vif.tx_clk);

      vif.col <= 1'b0;
      vif.crs <= 1'b0;

      `uvm_info("PHY_DRIVER",
        $sformatf("Manual collision DEASSERT at %0t", $time),
        UVM_MEDIUM)
    end
  endtask

// DEBUG MONITOR: print tx_en changes and collision events
task debug_tx_monitor();
  bit prev_tx_en = 0;
  bit prev_col = 0;
  forever begin
    @(posedge vif.tx_clk);
    if (vif.tx_en !== prev_tx_en) begin
      `uvm_info("PHY_DEBUG",$sformatf("TX_EN change: time=%0t tx_en=%0b", $time, vif.tx_en), UVM_LOW);
      prev_tx_en = vif.tx_en;
    end
    if (vif.col !== prev_col) begin
      `uvm_info("PHY_DEBUG",$sformatf("COL change: time=%0t col=%0b crs=%0b attempts_left=%0d",$time,vif.col,vif.crs,m_config.collisions_remaining), UVM_LOW);
      prev_col = vif.col;
    end
  end
endtask

// ------------------------------------------------------------------
// Assert CRS during MAC transmission (HALF DUPLEX requirement)
// ------------------------------------------------------------------
task drive_crs_during_tx();
  forever begin
    // Wait for TX to start
    @(posedge vif.tx_clk);
    if (m_config.crs_override) continue;  // Sequence controls CRS directly
    if (vif.tx_en === 1'b1) begin
      vif.crs <= 1'b1;

      // Hold CRS until TX ends
      wait (vif.tx_en === 1'b0);
      if (!m_config.crs_override)
        vif.crs <= 1'b0;
    end
  end
endtask



endclass : phy_driver