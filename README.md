# NIA PCIe Lib

A PCIe interface library and for the CPM5 block of AMD Versal devices,
the adaptor/interface utilize PCIE mode of CPM5 and convert the request and completion
interfaces to DMA required format, MSI/MSI-X adaptors are also provided.

The PCIe example is based on Alex Forencich's `verilog-pcie`.

Target device: AMD Versal CPM5, tested on VP1552 FPGA.

## Requirements

* `make check`: GNU make, bash, Python 3. No simulator and no Vivado.
* Simulation: cocotb and cocotbext-pcie, with Verilator 4.106 or newer, or Icarus Verilog
  10.3 or newer. `cocotb-config` must be on `PATH`.
* Image build: Vivado 2025.2 for the target part, on `PATH`.
* Programming and host test: Vivado or Vivado Lab with the JTAG drivers, on `PATH`, kernel
  headers for the running kernel, `sudo`, and a board in a slot of the machine that runs the
  test.

## User's Guide


### 1. Get the sources

    git clone https://github.com/nightseas/nia-pcie
    cd nia-pcie
    git submodule update --init --depth 1

The submodule is only needed when you want to build a DMA example design.

### 2. Check the repository

The self checking of scripts and repo.

    make check

### 3. Simulate

    make list          # what there is to run
    make sim           # run all of it

`make sim` must end with `0 failed`. To run less than everything:

    cd sim/gen5x8              && make    # one link generation
    cd sim/gen5x8/cqcc_gearbox && make    # one set

You can also choose the simulator:

    NIA_SIM_ARGS="SIM=verilator" make sim
    NIA_SIM_ARGS="SIM=icarus"    make sim

A set can declare itself unrunnable under one simulator by listing it in a `sim_skip` file beside
its `Makefile`. `make sim` reports such a set as `SKIPPED` with the reason and does not count it as
a failure. `sim/gen5x8/rq` is skipped under Verilator for this reason, so the Verilator run reports
`4 passed, 0 failed, 1 skipped` while Icarus runs all five.

Each set also has a mutation gate. It breaks the design on purpose, one defect at a time, and
requires the tests to catch every one. Run it when you have changed a module:

    cd sim/gen5x8/rq && ./mutate.sh

### 4. Build a device image

Source Vivado first, then choose the example design to build.

    source <path to Vivado>/settings64.sh

    make image                  # default: Gen4 x8
    NIA_CPM=GEN5 make image     # Gen5 x8

Built image `fpga.pdi` will be stored in:
`example/TU03/gen4x8/fpga/build_pdi/` or `example/TU03/gen5x8/fpga/build_pdi_1024/`.

    make clean                  # remove build output


### 5. Program the board

Source Vivado (or Lab edition), then check the setup before you write anything:

    source <path to Vivado or Vivado Lab>/settings64.sh
    cd example/TU03/hw

    PDI=<path to fpga.pdi> ./program.sh check
    PDI=<path to fpga.pdi> ./program.sh program

Then reboot the host to enumerate the PCIe endpoint:

    sudo reboot


### 6. Test

Test scripts are located in `example/TU03/hw`.

Check pcie link status using `lspci` or scripts.

    EXPECT_LNK_SPEED=16GT/s sudo -E ./check_pcie.sh all    # Gen4 x8
    EXPECT_LNK_SPEED=32GT/s sudo -E ./check_pcie.sh all    # Gen5 x8

Then build and load Kernel driver, run DMA test:

    ./run_dma.sh build                # build the reference driver\
    ./run_dma.sh load                 # load driver
    NIA_BENCH=1 ./run_dma.sh load     # load driver with bandwidth benchmark on varies of block size
    ./run_dma.sh unload               # unload driver

Scripts that can be used to test PCIe function on a board without driver.

    sudo python3 ./csr_probe.py --dma-selftest

