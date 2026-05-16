//////////////////////////////////////////////////////////////////////
////                                                              ////
////  can_id_filter.v                                             ////
////                                                              ////
////  16-entry parallel CAN ID filter for the bridge.             ////
////  Compares incoming CAN ID against a programmable table       ////
////  and outputs a filter_drop decision.                         ////
////                                                              ////
//////////////////////////////////////////////////////////////////////

`include "can_eth_bridge_defines.v"

module can_id_filter (
    input         clk,
    input         rst_n,

    // Filter configuration (from bridge_regs)
    input         filter_en,       // 1 = filtering active
    input         filter_mode,     // 0 = accept list, 1 = reject list
    input  [28:0] filter_table_0,
    input  [28:0] filter_table_1,
    input  [28:0] filter_table_2,
    input  [28:0] filter_table_3,
    input  [28:0] filter_table_4,
    input  [28:0] filter_table_5,
    input  [28:0] filter_table_6,
    input  [28:0] filter_table_7,
    input  [28:0] filter_table_8,
    input  [28:0] filter_table_9,
    input  [28:0] filter_table_10,
    input  [28:0] filter_table_11,
    input  [28:0] filter_table_12,
    input  [28:0] filter_table_13,
    input  [28:0] filter_table_14,
    input  [28:0] filter_table_15,

    // Frame to check
    input  [28:0] can_id,          // CAN identifier to compare
    input         check_valid,     // pulse: evaluate this ID now

    // Result
    output reg    filter_drop,     // 1 = drop this frame
    output reg    result_valid     // 1 = filter_drop is valid
);

    //----------------------------------------------------------
    // Combinational: 16 parallel comparators
    //----------------------------------------------------------
    wire [15:0] match;

    assign match[ 0] = (can_id == filter_table_0);
    assign match[ 1] = (can_id == filter_table_1);
    assign match[ 2] = (can_id == filter_table_2);
    assign match[ 3] = (can_id == filter_table_3);
    assign match[ 4] = (can_id == filter_table_4);
    assign match[ 5] = (can_id == filter_table_5);
    assign match[ 6] = (can_id == filter_table_6);
    assign match[ 7] = (can_id == filter_table_7);
    assign match[ 8] = (can_id == filter_table_8);
    assign match[ 9] = (can_id == filter_table_9);
    assign match[10] = (can_id == filter_table_10);
    assign match[11] = (can_id == filter_table_11);
    assign match[12] = (can_id == filter_table_12);
    assign match[13] = (can_id == filter_table_13);
    assign match[14] = (can_id == filter_table_14);
    assign match[15] = (can_id == filter_table_15);

    wire raw_hit = |match;  // OR-reduce: 1 if any entry matches

    //----------------------------------------------------------
    // Registered output: 1-cycle latency
    //----------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            filter_drop  <= 1'b0;
            result_valid <= 1'b0;
        end else begin
            result_valid <= check_valid;

            if (check_valid) begin
                if (!filter_en) begin
                    // Filter disabled: never drop
                    filter_drop <= 1'b0;
                end else begin
                    // Accept mode (0): drop if NOT in list
                    // Reject mode (1): drop if in list
                    filter_drop <= filter_mode ? raw_hit : ~raw_hit;
                end
            end
        end
    end

endmodule
