# nexys_a7.xdc - constraints for the RV32I core on the Nexys A7-100T.
#
# M7 (out-of-context synthesis of core_top): only the clock constraint is
# active. Board pin assignments below are commented out until the SoC top
# with real I/O lands in M8.

# Core clock target: 50 MHz to start (M7), push toward 100 MHz after.
create_clock -period 20.000 -name core_clk [get_ports clk]

## ---- M8: Nexys A7-100T board pins (uncomment when soc_top exists) ----
## 100 MHz board clock
# set_property -dict {PACKAGE_PIN E3 IOSTANDARD LVCMOS33} [get_ports clk100]
# create_clock -period 10.000 -name sys_clk [get_ports clk100]
## CPU reset button (active low)
# set_property -dict {PACKAGE_PIN C12 IOSTANDARD LVCMOS33} [get_ports resetn]
## USB-UART: FPGA TX -> host RX
# set_property -dict {PACKAGE_PIN D4 IOSTANDARD LVCMOS33} [get_ports uart_tx]
## LEDs LD0-LD15: H17 K15 J13 N14 R18 V17 U17 U16 V16 T15 U14 T16 V15 V14 V12 V11
## Switches SW0-SW15: J15 L16 M13 R15 R17 T18 U18 R13 T8 U8 R16 T13 H6 U12 U11 V10
