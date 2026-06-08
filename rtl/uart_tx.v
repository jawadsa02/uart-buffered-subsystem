// ============================================================================
// uart_tx.v — Parameterized UART transmitter (8N1)
// Part of the DLX-on-FPGA bring-up project (Cmod A7, Artix-7)
// Author: Jawad Saied Ahmed
//
// Single clock domain (matches the board's 12 MHz oscillator strategy).
// Start bit -> 8 data bits (LSB first) -> stop bit.
// ============================================================================
`timescale 1ns / 1ps
`default_nettype none

module uart_tx #(
    parameter integer CLK_FREQ_HZ = 12_000_000,  // Cmod A7 on-board oscillator
    parameter integer BAUD_RATE   = 115_200
) (
    input  wire       clk,
    input  wire       rst_n,      // active-low synchronous reset
    input  wire       tx_start,   // pulse: load tx_data and begin transmission
    input  wire [7:0] tx_data,
    output reg        tx,         // serial line (idle high)
    output wire       tx_busy
);

    localparam integer CLKS_PER_BIT = CLK_FREQ_HZ / BAUD_RATE;
    localparam [31:0]  CPB32        = CLKS_PER_BIT;
    localparam [15:0]  CNT_LAST     = CPB32[15:0] - 16'd1;

    // FSM states
    localparam [1:0] S_IDLE  = 2'd0,
                     S_START = 2'd1,
                     S_DATA  = 2'd2,
                     S_STOP  = 2'd3;

    reg [1:0]  state;
    reg [15:0] clk_cnt;
    reg [2:0]  bit_idx;
    reg [7:0]  data_reg;

    assign tx_busy = (state != S_IDLE);

    always @(posedge clk) begin
        if (!rst_n) begin
            state    <= S_IDLE;
            tx       <= 1'b1;       // line idles high
            clk_cnt  <= 16'd0;
            bit_idx  <= 3'd0;
            data_reg <= 8'd0;
        end else begin
            case (state)
                S_IDLE: begin
                    tx      <= 1'b1;
                    clk_cnt <= 16'd0;
                    bit_idx <= 3'd0;
                    if (tx_start) begin
                        data_reg <= tx_data;
                        state    <= S_START;
                    end
                end

                S_START: begin
                    tx <= 1'b0;     // start bit
                    if (clk_cnt == CNT_LAST) begin
                        clk_cnt <= 16'd0;
                        state   <= S_DATA;
                    end else
                        clk_cnt <= clk_cnt + 16'd1;
                end

                S_DATA: begin
                    tx <= data_reg[bit_idx];   // LSB first
                    if (clk_cnt == CNT_LAST) begin
                        clk_cnt <= 16'd0;
                        if (bit_idx == 3'd7) begin
                            bit_idx <= 3'd0;
                            state   <= S_STOP;
                        end else
                            bit_idx <= bit_idx + 3'd1;
                    end else
                        clk_cnt <= clk_cnt + 16'd1;
                end

                S_STOP: begin
                    tx <= 1'b1;     // stop bit
                    if (clk_cnt == CNT_LAST) begin
                        clk_cnt <= 16'd0;
                        state   <= S_IDLE;
                    end else
                        clk_cnt <= clk_cnt + 16'd1;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

`ifdef FORMAL
    // Internal invariants proved by SymbiYosys (see formal/uart_tx.sby)
    reg f_past_valid = 1'b0;
    always @(posedge clk) f_past_valid <= 1'b1;

    always @(posedge clk) if (f_past_valid && rst_n) begin
        // FSM state is always legal
        assert (state <= S_STOP);
        // busy if and only if a frame is in flight
        assert (tx_busy == (state != S_IDLE));
        // the line idles high
        if (state == S_IDLE) assert (tx == 1'b1);
        // start bit drives the line low
        if (state == S_DATA || state == S_STOP) assert (clk_cnt < CLKS_PER_BIT);
        // bit index stays in range
        assert (bit_idx <= 3'd7);
    end

    // cover: a complete frame is transmittable
    reg f_saw_busy = 1'b0;
    always @(posedge clk) if (f_past_valid && rst_n) begin
        if (tx_busy) f_saw_busy <= 1'b1;
        cover (f_saw_busy && !tx_busy);   // frame completed
    end
`endif

endmodule

`default_nettype wire
