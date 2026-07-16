# RV32I 5-stage pipelined core - simulation with Icarus Verilog
IV    = iverilog -g2012 -I rtl
VVP   = vvp
RTL   = rtl/alu.v rtl/regfile.v rtl/imm_gen.v rtl/control_unit.v rtl/riscv_core.v
TB    = tb/tb_riscv_core.v
BUILD = build

.PHONY: test test-core test-isa asm asm-isa wave clean synth
test: test-core test-isa ## run the pipeline demo AND the full ISA-coverage test

test-core: asm ## sum/forwarding/load-use demo program
	@mkdir -p $(BUILD)
	$(IV) -o $(BUILD)/sim.vvp $(RTL) $(TB)
	$(VVP) $(BUILD)/sim.vvp

test-isa: asm-isa ## exercises every supported RV32I instruction
	@mkdir -p $(BUILD)
	$(IV) -o $(BUILD)/isa.vvp $(RTL) tb/tb_riscv_isa.v
	$(VVP) $(BUILD)/isa.vvp

asm: ## assemble tb/program.asm -> program.hex (padded to the 64-word ROM)
	python3 tools/assemble.py tb/program.asm program.hex 64

asm-isa: ## assemble tb/program_isa.asm -> program_isa.hex
	python3 tools/assemble.py tb/program_isa.asm program_isa.hex 64

wave: asm ## regenerate the reference pipeline waveform SVG
	@mkdir -p $(BUILD)
	$(IV) -o $(BUILD)/sim.vvp $(RTL) $(TB)
	cd docs && cp ../program.hex . && $(VVP) ../$(BUILD)/sim.vvp >/dev/null
	python3 tools/vcd2svg.py docs/riscv.vcd docs/riscv_wave.svg \
		pc if_instr stall pcsrc branch_taken \
		--title "RV32I pipeline: load-use hazard triggers a 1-cycle stall" \
		--from 650000 --to 850000

clean:
	rm -rf $(BUILD) docs/*.vcd docs/program.hex docs/program_isa.hex

synth: ## quick synthesizability check with Yosys
	yosys -p "read_verilog -I rtl rtl/alu.v rtl/regfile.v rtl/imm_gen.v rtl/control_unit.v rtl/riscv_core.v; synth -top riscv_core"
