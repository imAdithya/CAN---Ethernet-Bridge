//////////////////////////////////////////////////////////////////////
////                                                              ////
////  can_tx_queue.v                                              ////
////                                                              ////
////  8-deep synchronous FIFO for buffering CAN frames in the     ////
////  downstream path (ETH → CAN). Absorbs the speed gap          ////
////  between fast Ethernet reception and slow CAN transmission.   ////
////                                                              ////
//////////////////////////////////////////////////////////////////////

`include "can_eth_bridge_defines.v"

module can_tx_queue (
    input          clk,
    input          rst_n,

    // Write port (from downstream decap)
    input          push,
    input  [28:0]  data_id,       // CAN identifier
    input   [3:0]  data_dlc,      // Data Length Code
    input          data_eff,      // Extended Frame Format
    input          data_rtr,      // Remote Transmit Request
    input  [63:0]  data_payload,  // CAN data bytes (up to 8)

    // Read port (to CAN TX writer)
    input          pop,
    output [28:0]  q_id,
    output  [3:0]  q_dlc,
    output         q_eff,
    output         q_rtr,
    output [63:0]  q_payload,

    // Status
    output         full,
    output         empty,
    output  [3:0]  depth
);

    //----------------------------------------------------------
    // Parameters
    //----------------------------------------------------------
    localparam DEPTH     = `QUEUE_DEPTH;       // 8
    localparam PTR_W     = 3;                  // log2(8)

    // Pack all CAN frame fields into one wide word
    // 29 + 4 + 1 + 1 + 64 = 99 bits
    localparam ENTRY_W   = 99;

    //----------------------------------------------------------
    // Internal storage
    //----------------------------------------------------------
    reg [ENTRY_W-1:0] mem [0:DEPTH-1];
    reg [PTR_W:0]     wr_ptr;    // extra bit for full/empty detection
    reg [PTR_W:0]     rd_ptr;

    //----------------------------------------------------------
    // Pack / Unpack
    //----------------------------------------------------------
    wire [ENTRY_W-1:0] data_in = {data_id, data_dlc, data_eff, data_rtr, data_payload};
    wire [ENTRY_W-1:0] data_out = mem[rd_ptr[PTR_W-1:0]];

    assign q_id      = data_out[98:70];
    assign q_dlc     = data_out[69:66];
    assign q_eff     = data_out[65];
    assign q_rtr     = data_out[64];
    assign q_payload = data_out[63:0];

    //----------------------------------------------------------
    // Status signals
    //----------------------------------------------------------
    wire ptr_match = (wr_ptr[PTR_W-1:0] == rd_ptr[PTR_W-1:0]);
    wire msb_diff  = (wr_ptr[PTR_W] != rd_ptr[PTR_W]);

    assign full  = ptr_match & msb_diff;
    assign empty = ptr_match & ~msb_diff;
    assign depth = wr_ptr - rd_ptr;

    //----------------------------------------------------------
    // Write logic
    //----------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= {(PTR_W+1){1'b0}};
        end else if (push && !full) begin
            mem[wr_ptr[PTR_W-1:0]] <= data_in;
            wr_ptr <= wr_ptr + 1'b1;
        end
    end

    //----------------------------------------------------------
    // Read logic
    //----------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_ptr <= {(PTR_W+1){1'b0}};
        end else if (pop && !empty) begin
            rd_ptr <= rd_ptr + 1'b1;
        end
    end

endmodule
