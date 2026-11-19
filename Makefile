TOP   := sha3_core
RTL   := $(wildcard rtl/*.sv)
TB    := tb/tb_sha3.sv
BUILD := build

.PHONY: test lint synth clean

test: $(BUILD)/vectors.txt
	iverilog -g2012 -o $(BUILD)/tb.vvp $(RTL) $(TB)
	vvp -n $(BUILD)/tb.vvp +vectors=$(BUILD)/vectors.txt

$(BUILD)/vectors.txt: scripts/gen_vectors.py
	@mkdir -p $(BUILD)
	python3 scripts/gen_vectors.py $@

lint:
	verilator --lint-only -Wall -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL --top-module $(TOP) $(RTL)

synth:
	@mkdir -p $(BUILD)
	yosys -q -p "read_verilog -sv $(RTL); synth -top $(TOP); tee -o $(BUILD)/synth_stat.txt stat"
	@grep -E "cells$$|Number of cells|_DFF|\$$_" $(BUILD)/synth_stat.txt | head -40

clean:
	rm -rf $(BUILD)
