# Digital-Design

A personal library of small, reusable, synthesizable SystemVerilog building
blocks: arbiters, FIFOs, clock-domain-crossing primitives, skid buffers, clock
dividers/gates/muxes, and a few data-path helpers. Each module is
parameterized, carries a header comment explaining what it does and how to use
it safely, and — where practical — comes with a self-checking testbench.

## Layout

| Directory        | Contents |
|------------------|----------|
| `arbiters/`      | Priority, round-robin (masked and pointer), matrix-LRU, time-slice, and a binary-tree round-robin arbiter |
| `fifos/`         | Synchronous FIFO (power-of-two pointers), synchronous FIFO for arbitrary depth (counter based), and a Gray-code async FIFO |
| `synchronizers/` | Multi-flop synchronizer, 2-/4-phase request-ack CDC handshakes (hand-rolled and FSM), a fast-to-slow synchronous crossing, a Gray-counter pulse synchronizer, and a stretch-and-resync pulse crossing |
| `skid_buffers/`  | Full-throughput skid buffer and a lighter spill register |
| `clock_common/`  | Clock inverter / OR / gate, ripple and single-counter dividers, combinational 2:1 and 4:1 clock muxes, and a glitchless clock mux |
| `common/`        | LFSR and a population counter (naive and O(log2(N)) tree) |
| `data_width_convertors/` | Parallel/serial converters and a variable-size-to-fixed-size data-width gearbox |
| `*/tb/`          | Self-checking testbenches (kept out of the synthesizable path) |

## Conventions

- **Ports**: `i_` / `o_` prefixes for inputs and outputs; `i_clk`, active-low
  `i_reset_n`. Data-path blocks use `i_valid` / `o_ready` on the input side and
  `o_valid` / `i_ready` on the output side.
- **Parameters**: `parameter int unsigned` for sizes; derived values are
  `localparam`.
- **Reset**: synchronous unless the block is a clock/CDC primitive that needs
  async assertion (dividers, glitchless mux, the async-reset mode of `sync`).
- **Assertions**: elaboration-time parameter checks are guarded with
  `` `ifdef SIM ``.
- **Foundry cells**: clock and synchronizer primitives have a
  `` `ifdef FOUNDRY_LIBCELL `` branch where the behavioral logic is replaced by
  a placeholder library-cell instance to be remapped in a real flow.

## Simulation

Testbenches are written for **Icarus Verilog** (`iverilog -g2012`) and every
synthesizable file also lints clean under **Verilator** (`verilator
--lint-only -Wall`). Each testbench header lists its exact command line; the
general form, run from a topic directory, is:

```sh
iverilog -g2012 -DSIM -o sim tb/tb_<name>.sv <rtl files...> && vvp sim
```

A passing run prints `RESULT: PASS`. Many testbenches take `-P<tb>.NAME=value`
overrides (widths, depths, cycle counts) and macro selectors (e.g.
`-DARB_MODULE=round_robin_arb_ptr`, `-DFIFO_MODULE=sync_fifo_variable_depth`).

## Verification status

| Module | Testbench | Notes |
|--------|-----------|-------|
| `priority_arb` | `arbiters/tb/tb_priority_arb.sv` | golden state machine, one-hot / hold-until-taken |
| `round_robin_arb`, `round_robin_arb_ptr` | `arbiters/tb/tb_round_robin_arb.sv` | rotating-pointer model + starvation bound |
| `nxn_matrix_lru_arb` | `arbiters/tb/tb_nxn_matrix_lru_arb.sv` | ordered-list LRU model + fairness bound |
| `time_slice_arb` | `arbiters/tb/tb_time_slice_arb.sv` | slot model + one-grant-per-frame |
| `bin_tree_arb_4` | `arbiters/tb/tb_bin_tree_arb.sv` | structural contract + bounded wait |
| `sync_fifo`, `sync_fifo_variable_depth` | `fifos/tb/tb_sync_fifo.sv` | behavioral-queue model, phased stimulus, struct payloads |
| `async_fifo` | `fifos/tb/tb_async_fifo.sv` | dual-clock, Gray-code check, occupancy model |
| `sync` | via `async_fifo` / `anti_glitch_clkmux` | — |
| `async_2_phase_hs`, `async_4_phase_hs`, `async_4_phase_hs_fsm`, `sync_2_phase_hs`, `sync_4_phase_hs` | `synchronizers/tb/tb_async_hs.sv` | dual-clock data-integrity model |
| `pulse_sync` | `synchronizers/tb/tb_pulse_sync.sv` | dual-clock, count conservation, drop / `o_error` on overrun, one-cycle strobe |
| `pulse_stretch_sync` | `synchronizers/tb/tb_pulse_stretch_sync.sv` | dual-clock, count conservation, one-cycle strobe (for source pulses sparse enough to respect the clock ratio) |
| `fast2slow_sync_crossing` | — | synchronous rational crossing; correctness depends on PD/STA closure between the related clocks, per the module header |
| `skid_buf`, `spill_register` | `skid_buffers/tb/tb_skid_buffer.sv` | stream integrity + stall stability |
| `lfsr` | `common/tb/tb_lfsr.sv` | next-state model, measured cycle length, lock-up |
| `population_count`, `population_count_naive` | `common/tb/tb_population_count.sv` | cross-checked against each other and `$countones()`; tree is power-of-2 only |
| `parallel_to_serial_converter`, `serial_to_parallel_converter` | `data_width_convertors/tb/tb_serdes.sv` | individual + loopback |
| `gearbox_data_word_converter` | `data_width_convertors/tb/tb_gearbox_data_word_converter.sv` | byte-queue model, up / down / equal width |
| `clkdiv2/4/8`, `clkdiv_sync` | `clock_common/tb/tb_clkdiv.sv` | frequency / duty / phase alignment |
| `clkgate` | `clock_common/tb/tb_clkgate.sv` | glitch-free enable |
| `clkmux2`, `clkmux4` | `clock_common/tb/tb_clkmux.sv` | selection + quantified glitch behavior |
| `anti_glitch_clkmux` | `clock_common/tb/tb_anti_glitch_clkmux.sv` | mutual exclusion, no runt pulses |
| `clkinv`, `clkor` | via other testbenches | trivial |
