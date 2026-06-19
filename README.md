<div align="center">

# Buffered UART Subsystem

A register-buffered UART built from three blocks that were each verified separately — then composed and tested end-to-end.

![Verilog](https://img.shields.io/badge/RTL-Verilog--2005-1ABC9C?style=flat-square)
![Lint](https://img.shields.io/badge/Verilator-0%20warnings-2ECC71?style=flat-square)
![E2E](https://img.shields.io/badge/End--to--end-12%20bytes%20PASS-2ECC71?style=flat-square)
![Synth](https://img.shields.io/badge/Yosys-1138%20cells-3498DB?style=flat-square)
![RTL CI](https://github.com/jawadsa02/uart-buffered-subsystem/actions/workflows/ci.yml/badge.svg)

</div>

---

## Context

Writing individual modules is one skill. Wiring them into a subsystem with correct flow control is another.

This repo takes `uart_tx` and `uart_rx` from the [DLX bring-up project](https://github.com/jawadsa02/dlx-fpga-resa-bringup) and two instances of the [formally verified FIFO](https://github.com/jawadsa02/sync-fifo-verified), then adds the glue logic: automatic TX loading, RX capture, occupancy counters, and overrun detection. For the scoreboard + coverage checking pattern in isolation, see [ai-verification-copilot](https://github.com/jawadsa02/ai-verification-copilot).

| Block | Role | Verified in |
|---|---|---|
| `uart_tx` | Serialize bytes onto the line | [dlx-fpga-resa-bringup](https://github.com/jawadsa02/dlx-fpga-resa-bringup) |
| `uart_rx` | Deserialize the line into bytes | [dlx-fpga-resa-bringup](https://github.com/jawadsa02/dlx-fpga-resa-bringup) |
| `sync_fifo` ×2 | TX and RX buffering | [sync-fifo-verified](https://github.com/jawadsa02/sync-fifo-verified) |
| `uart_buffered` | Integration + flow control | **this repo** |

## Block diagram

```mermaid
flowchart LR
    HOST[Host interface] -->|wr_en, wr_data| TXF[TX FIFO]
    TXF -->|load when idle| TX[uart_tx]
    TX -->|txd| LINE((serial line))
    LINE -->|rxd| RX[uart_rx]
    RX -->|rx_valid| RXF[RX FIFO]
    RXF -->|rd_en, rd_data| HOST
    RXF -.->|overflow| OV[rx_overrun]
```

**Host side:** push bytes with `wr_en`/`wr_data` (backpressure via `tx_full`). Pop received bytes with `rd_en`/`rd_data` (`rx_empty` when nothing to read). `tx_level` and `rx_level` show how full each buffer is.

## Verification

```mermaid
flowchart TB
    subgraph upstream["Upstream (already proven)"]
        U1[uart_tx — formal + sim]
        U2[uart_rx — formal + sim]
        U3[sync_fifo — formal + sim]
    end
    subgraph here["This repo"]
        E2E[Loopback scoreboard<br/>12 bytes bit-exact]
        LINT[Verilator lint]
        SYN[Yosys synth — 1138 cells]
    end
    upstream --> E2E
    E2E --> LINT --> SYN
```

| Check | Result |
|---|---|
| Full path TX FIFO → serial → RX FIFO | 12/12 bytes bit-exact |
| Burst write faster than line rate | `tx_full` never asserted at depth 16 |
| Byte ordering | In-order scoreboard pass |
| RX overrun under continuous drain | `rx_overrun` never asserted |
| Synthesis | 1138 cells (Yosys) |
| Lint | 0 warnings (Verilator `-Wall`) |

### Simulation waveform

<p align="center">
  <img src="docs/pipeline_waveform.png" alt="End-to-end UART pipeline waveform" width="90%"/>
</p>

<p align="center"><em>Twelve bytes pushed into the TX FIFO, serialized on the line, and read back in order: 0x00, FF, 55, AA, 13, 8C, 7E, 01, C3, 3C, F0, 0F.</em></p>

## Run locally

```bash
make test     # end-to-end loopback (Icarus)
make synth    # Yosys synthesis + cell report
make lint     # Verilator -Wall
```

CI runs all three on every push.

## Layout

```
.
├── rtl/
│   ├── uart_buffered.v   # subsystem integration (this repo)
│   ├── uart_tx.v         # from dlx-fpga-resa-bringup
│   ├── uart_rx.v
│   └── sync_fifo.v       # from sync-fifo-verified
├── tb/tb_uart_buffered.v
├── docs/pipeline_waveform.png
└── Makefile · .github/workflows/ci.yml
```

---

<div align="center">

[Portfolio](https://jawad-saied-ahmed.netlify.app) · [LinkedIn](https://linkedin.com/in/jawadsaidahmed) · [GitHub](https://github.com/jawadsa02)

</div>
