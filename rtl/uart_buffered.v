// ============================================================================
// uart_buffered.v — Register-buffered UART subsystem
// Author: Jawad Saied Ahmed
//
// Composes three independently-verified blocks into one subsystem:
//
//   write ─►┌──────────┐  tx_start  ┌─────────┐  txd
//           │ TX FIFO  │───────────►│ uart_tx │──────►  (serial out)
//           │(sync_fifo)│  pop on    └─────────┘
//           └──────────┘  load
//
//   read  ◄─┌──────────┐  rx_valid  ┌─────────┐  rxd
//           │ RX FIFO  │◄───────────│ uart_rx │◄─────  (serial in)
//           │(sync_fifo)│  push      └─────────┘
//           └──────────┘
//
// The user pushes bytes into the TX FIFO and pops received bytes from the
// RX FIFO; the subsystem handles serialization, flow control and buffering.
// Each sub-block is formally verified / scoreboard-tested in its own repo;
// here the *integration* is verified end-to-end (see tb/tb_uart_buffered.v).
// ============================================================================
`timescale 1ns / 1ps
`default_nettype none

module uart_buffered #(
    parameter integer CLK_FREQ_HZ = 12_000_000,
    parameter integer BAUD_RATE   = 115_200,
    parameter integer FIFO_DEPTH  = 16
) (
    input  wire       clk,
    input  wire       rst_n,

    // write side (host -> UART)
    input  wire       wr_en,
    input  wire [7:0] wr_data,
    output wire       tx_full,      // TX FIFO full — apply backpressure

    // read side (UART -> host)
    input  wire       rd_en,
    output wire [7:0] rd_data,
    output wire       rx_empty,     // RX FIFO empty — nothing to read
    output wire       rx_overrun,   // a byte arrived while RX FIFO was full

    // serial pins
    output wire       txd,
    input  wire       rxd,

    // buffer occupancy (status / flow monitoring)
    output wire [$clog2(FIFO_DEPTH):0] tx_level,
    output wire [$clog2(FIFO_DEPTH):0] rx_level
);

    // ----------------------------------------------------------- TX path
    wire        txf_empty;
    wire [7:0]  txf_dout;
    wire        tx_busy;

    // load the transmitter whenever it is idle and the TX FIFO has data
    wire tx_load = !tx_busy && !txf_empty;

    sync_fifo #(.WIDTH(8), .DEPTH(FIFO_DEPTH)) tx_fifo (
        .clk(clk), .rst_n(rst_n),
        .wr_en(wr_en),   .wr_data(wr_data), .full(tx_full),
        .rd_en(tx_load), .rd_data(txf_dout), .empty(txf_empty),
        .count(tx_level)
    );

    uart_tx #(.CLK_FREQ_HZ(CLK_FREQ_HZ), .BAUD_RATE(BAUD_RATE)) u_tx (
        .clk(clk), .rst_n(rst_n),
        .tx_start(tx_load), .tx_data(txf_dout),
        .tx(txd), .tx_busy(tx_busy)
    );

    // ----------------------------------------------------------- RX path
    wire        rx_valid;
    wire [7:0]  rx_byte;
    wire        rxf_full;

    uart_rx #(.CLK_FREQ_HZ(CLK_FREQ_HZ), .BAUD_RATE(BAUD_RATE)) u_rx (
        .clk(clk), .rst_n(rst_n),
        .rx(rxd),
        .rx_data(rx_byte), .rx_valid(rx_valid)
    );

    // a received byte that arrives while the RX FIFO is full is dropped;
    // flag it so the host can detect overrun
    assign rx_overrun = rx_valid && rxf_full;

    sync_fifo #(.WIDTH(8), .DEPTH(FIFO_DEPTH)) rx_fifo (
        .clk(clk), .rst_n(rst_n),
        .wr_en(rx_valid), .wr_data(rx_byte), .full(rxf_full),
        .rd_en(rd_en),    .rd_data(rd_data), .empty(rx_empty),
        .count(rx_level)
    );

endmodule

`default_nettype wire
