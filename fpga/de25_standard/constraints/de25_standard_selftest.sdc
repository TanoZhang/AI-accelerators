create_clock -name CLOCK_50 -period 20.000 [get_ports {CLOCK_50}]

# KEY[0] asynchronously asserts reset. Deassertion is synchronized by two
# flip-flops inside de25_standard_selftest_top.
set_false_path -from [get_ports {KEY[0]}] -to [get_registers {*reset_sync_q*}]

# The remaining pushbuttons and slide switches are asynchronous board controls.
# The LEDs and seven-segment displays are human-visible status outputs and do
# not have external synchronous timing requirements.
set_false_path -from [get_ports {KEY[1] KEY[2] KEY[3] SW[*]}]
set_false_path -to [get_ports {LEDR[*] HEX0[*] HEX1[*] HEX2[*] HEX3[*] HEX4[*] HEX5[*]}]
