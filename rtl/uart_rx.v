// ============================================================================
// uart_rx.v — Parameterized UART receiver (8N1)
// Part of the DLX-on-FPGA bring-up project (Cmod A7, Artix-7)
// Author: Jawad Saied Ahmed
//
// Mid-bit sampling: after detecting the start-bit edge, waits half a bit
// period to land in the middle of the start bit, then samples each data
// bit at its center — maximum timing margin against baud-rate mismatch.
// 2-FF synchronizer on the rx input (async-safe).
// ============================================================================
`timescale 1ns / 1ps
`default_nettype none

module uart_rx #(
    parameter integer CLK_FREQ_HZ = 12_000_000,  // Cmod A7 on-board oscillator
    parameter integer BAUD_RATE   = 115_200
) (
    input  wire       clk,
    input  wire       rst_n,      // active-low synchronous reset
    input  wire       rx,         // serial line (idle high)
    output reg  [7:0] rx_data,
    output reg        rx_valid    // 1-cycle pulse when rx_data is fresh
);

    localparam integer CLKS_PER_BIT = CLK_FREQ_HZ / BAUD_RATE;
    localparam [31:0]  CPB32        = CLKS_PER_BIT;
    localparam [15:0]  CNT_LAST     = CPB32[15:0] - 16'd1;
    localparam [15:0]  CNT_HALF     = CPB32[16:1] - 16'd1;   // (CPB/2) - 1

    localparam [1:0] S_IDLE  = 2'd0,
                     S_START = 2'd1,
                     S_DATA  = 2'd2,
                     S_STOP  = 2'd3;

    // 2-FF synchronizer — rx is asynchronous to our clock
    reg rx_meta, rx_sync;
    always @(posedge clk) begin
        rx_meta <= rx;
        rx_sync <= rx_meta;
    end

    reg [1:0]  state;
    reg [15:0] clk_cnt;
    reg [2:0]  bit_idx;

    always @(posedge clk) begin
        if (!rst_n) begin
            state    <= S_IDLE;
            clk_cnt  <= 16'd0;
            bit_idx  <= 3'd0;
            rx_data  <= 8'd0;
            rx_valid <= 1'b0;
        end else begin
            rx_valid <= 1'b0;   // default: single-cycle pulse

            case (state)
                S_IDLE: begin
                    clk_cnt <= 16'd0;
                    bit_idx <= 3'd0;
                    if (rx_sync == 1'b0)            // start-bit edge detected
                        state <= S_START;
                end

                // wait to the MIDDLE of the start bit, re-validate it
                S_START: begin
                    if (clk_cnt == CNT_HALF) begin
                        clk_cnt <= 16'd0;
                        if (rx_sync == 1'b0)
                            state <= S_DATA;        // genuine start bit
                        else
                            state <= S_IDLE;        // glitch — reject
                    end else
                        clk_cnt <= clk_cnt + 16'd1;
                end

                // sample each data bit at its center (LSB first)
                S_DATA: begin
                    if (clk_cnt == CNT_LAST) begin
                        clk_cnt          <= 16'd0;
                        rx_data[bit_idx] <= rx_sync;
                        if (bit_idx == 3'd7) begin
                            bit_idx <= 3'd0;
                            state   <= S_STOP;
                        end else
                            bit_idx <= bit_idx + 3'd1;
                    end else
                        clk_cnt <= clk_cnt + 16'd1;
                end

                // sample the stop bit at its center; assert valid if high
                S_STOP: begin
                    if (clk_cnt == CNT_LAST) begin
                        clk_cnt <= 16'd0;
                        if (rx_sync == 1'b1)
                            rx_valid <= 1'b1;       // good frame
                        // framing error: silently drop (could add error flag)
                        state <= S_IDLE;
                    end else
                        clk_cnt <= clk_cnt + 16'd1;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule

`default_nettype wire
