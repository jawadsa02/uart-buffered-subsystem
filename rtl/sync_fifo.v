// ============================================================================
// sync_fifo.v — Parameterized synchronous FIFO
// Author: Jawad Saied Ahmed
//
// Classic single-clock FIFO with registered count, full/empty flags and
// first-word fall-through read data. Verified three ways:
//   1. Self-checking simulation testbench (scoreboard, random traffic)
//   2. Formal verification (SymbiYosys: invariants + data-integrity, BMC+cover)
//   3. Synthesis gate (Yosys) — proves the RTL is synthesizable
// ============================================================================
`timescale 1ns / 1ps
`default_nettype none

module sync_fifo #(
    parameter integer WIDTH = 8,
    parameter integer DEPTH = 16,                 // must be a power of two
    parameter integer AW    = $clog2(DEPTH)
) (
    input  wire             clk,
    input  wire             rst_n,     // active-low synchronous reset

    input  wire             wr_en,
    input  wire [WIDTH-1:0] wr_data,
    output wire             full,

    input  wire             rd_en,
    output wire [WIDTH-1:0] rd_data,   // first-word fall-through
    output wire             empty,

    output reg  [AW:0]      count      // 0 .. DEPTH
);

    reg [WIDTH-1:0] mem [0:DEPTH-1];
    reg [AW-1:0]    wr_ptr, rd_ptr;

    wire do_write = wr_en && !full;
    wire do_read  = rd_en && !empty;

    assign full    = (count == DEPTH[AW:0]);
    assign empty   = (count == 0);
    assign rd_data = mem[rd_ptr];

    always @(posedge clk) begin
        if (!rst_n) begin
            wr_ptr <= {AW{1'b0}};
            rd_ptr <= {AW{1'b0}};
            count  <= {(AW+1){1'b0}};
        end else begin
            if (do_write) begin
                mem[wr_ptr] <= wr_data;
                wr_ptr      <= wr_ptr + 1'b1;
            end
            if (do_read)
                rd_ptr <= rd_ptr + 1'b1;

            case ({do_write, do_read})
                2'b10:   count <= count + 1'b1;
                2'b01:   count <= count - 1'b1;
                default: count <= count;          // 00 or simultaneous 11
            endcase
        end
    end

`ifdef FORMAL
    // ------------------------------------------------------------------
    // Internal invariants (proved by SymbiYosys, see formal/fifo.sby).
    // Inside the module we have direct access to pointers and memory.
    // ------------------------------------------------------------------
    reg f_past_valid = 1'b0;
    always @(posedge clk) f_past_valid <= 1'b1;

    always @(posedge clk) if (f_past_valid && rst_n) begin
        // P1: count is bounded
        assert (count <= DEPTH[AW:0]);
        // P2: flags always consistent with count
        assert (empty == (count == 0));
        assert (full  == (count == DEPTH[AW:0]));
        // P3: pointer difference always equals count (mod DEPTH)
        assert (((wr_ptr - rd_ptr) & {AW{1'b1}}) == count[AW-1:0]);
    end
`endif

endmodule

`default_nettype wire
