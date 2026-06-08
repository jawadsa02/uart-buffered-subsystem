// ============================================================================
// tb_uart_buffered.v — END-TO-END integration test for uart_buffered
//
// Wires txd back into rxd (loopback) so a byte pushed into the TX FIFO must
// travel: TX FIFO -> uart_tx -> serial -> uart_rx -> RX FIFO -> read port,
// and emerge bit-exact. A scoreboard tracks every byte written; every byte
// read is checked. Exercises FIFO buffering by bursting many bytes in before
// draining. $fatal(1) on mismatch -> CI fails.
// ============================================================================
`timescale 1ns / 1ps
`default_nettype none

module tb_uart_buffered;

    // small clk/baud ratio keeps the end-to-end sim fast
    localparam CLK_FREQ_HZ = 1_000_000;
    localparam BAUD_RATE   = 250_000;       // CLKS_PER_BIT = 4 (fast sim)
    localparam FIFO_DEPTH  = 16;
    localparam CLK_PERIOD  = 1000;          // ns
    localparam N_BYTES     = 12;

    reg        clk = 0;
    reg        rst_n;
    reg        wr_en, rd_en;
    reg  [7:0] wr_data;
    wire       tx_full, rx_empty, rx_overrun;
    wire [7:0] rd_data;
    wire       serial;

    integer errors = 0, sent = 0, recv = 0;
    reg [7:0] expected [0:255];
    integer wptr = 0, rptr = 0;

    uart_buffered #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ), .BAUD_RATE(BAUD_RATE), .FIFO_DEPTH(FIFO_DEPTH)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .wr_en(wr_en), .wr_data(wr_data), .tx_full(tx_full),
        .rd_en(rd_en), .rd_data(rd_data), .rx_empty(rx_empty), .rx_overrun(rx_overrun),
        .txd(serial), .rxd(serial)              // loopback
    );

    always #(CLK_PERIOD/2) clk = ~clk;

    // scoreboard: check each byte popped from the RX FIFO
    always @(posedge clk) if (rst_n) begin
        if (rd_en && !rx_empty) begin
            if (rd_data !== expected[rptr]) begin
                $display("  [FAIL] byte %0d: expected 0x%02h got 0x%02h", rptr, expected[rptr], rd_data);
                errors = errors + 1;
            end else
                $display("  [PASS] byte %0d 0x%02h made it through the full pipeline", rptr, rd_data);
            rptr = rptr + 1; recv = recv + 1;
        end
        if (rx_overrun) begin
            $display("  [FAIL] RX overrun — RX FIFO overflowed"); errors = errors + 1;
        end
    end

    task automatic push(input [7:0] d);
        begin
            @(posedge clk); #1;
            while (tx_full) begin @(posedge clk); #1; end
            wr_data = d; wr_en = 1; expected[wptr] = d; wptr = wptr + 1; sent = sent + 1;
            @(posedge clk); #1; wr_en = 0;
        end
    endtask

    integer i;
    initial begin
        $dumpfile("tb_uart_buffered.vcd");
        $dumpvars(0, tb_uart_buffered);
        $display("=== uart_buffered end-to-end integration test ===");

        rst_n = 0; wr_en = 0; rd_en = 0; wr_data = 0;
        repeat (5) @(posedge clk); rst_n = 1; @(posedge clk);

        // burst several bytes into the TX FIFO faster than they can serialize,
        // exercising the buffering, then keep the RX read side draining
        rd_en = 1;                                  // continuously pop RX FIFO
        fork
            begin
                push(8'h00); push(8'hFF); push(8'h55); push(8'hAA);
                push(8'h13); push(8'h8C); push(8'h7E); push(8'h01);
                push(8'hC3); push(8'h3C); push(8'hF0); push(8'h0F);
            end
        join

        // wait for the pipeline to fully drain
        i = 0;
        while (recv < N_BYTES && i < 4000) begin @(posedge clk); i = i + 1; end
        repeat (40) @(posedge clk);
        rd_en = 0;

        $display("----------------------------------------");
        $display("sent %0d, received %0d", sent, recv);
        if (recv !== N_BYTES) begin
            $display("  [FAIL] only %0d of %0d bytes recovered", recv, N_BYTES);
            errors = errors + 1;
        end
        if (errors == 0) begin
            $display("TEST PASSED: %0d bytes through TX-FIFO -> serial -> RX-FIFO, bit-exact", N_BYTES);
            $finish(0);
        end else begin
            $display("TEST FAILED: %0d errors", errors);
            $fatal(1);
        end
    end

    initial begin
        #5_000_000;
        $display("TEST FAILED: watchdog timeout");
        $fatal(1);
    end

endmodule

`default_nettype wire
