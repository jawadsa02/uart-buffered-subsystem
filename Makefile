IVERILOG := iverilog -g2012 -Wall

.PHONY: test lint synth clean

test:
	$(IVERILOG) -o sim_buf tb/tb_uart_buffered.v rtl/*.v
	vvp sim_buf

lint:
	verilator --lint-only -Wall -Wno-DECLFILENAME --top-module uart_buffered rtl/*.v

synth:
	yosys -p "read_verilog rtl/sync_fifo.v rtl/uart_tx.v rtl/uart_rx.v rtl/uart_buffered.v; synth -top uart_buffered; stat" | tee /tmp/syn.log
	grep -q "Number of cells" /tmp/syn.log

clean:
	rm -f sim_* *.vcd
