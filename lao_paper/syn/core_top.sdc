######################################################################
# Standard Design Constraints (SDC) for VX_core_top
######################################################################

# Define clock port name (usually 'clk')
set CLK_PORT "clk"

# Define target clock period in nanoseconds (e.g. 5.0ns -> 200MHz)
# Allow external override from synthesis TCL script
if {![info exists CLK_PERIOD]} {
    set CLK_PERIOD 2.5
}

# Create the clock
create_clock -name VCLK -period $CLK_PERIOD [get_ports $CLK_PORT]

# Set clock uncertainties (jitter, skew)
set_clock_uncertainty -setup 0.2 [get_clocks VCLK]
set_clock_uncertainty -hold 0.1 [get_clocks VCLK]
set_clock_transition 0.1 [get_clocks VCLK]

# Set input/output delays (assume 20% of clock period outside)
set IN_DELAY  [expr 0.2 * $CLK_PERIOD]
set OUT_DELAY [expr 0.2 * $CLK_PERIOD]

set_input_delay $IN_DELAY -clock VCLK [remove_from_collection [all_inputs] [get_ports $CLK_PORT]]
set_output_delay $OUT_DELAY -clock VCLK [all_outputs]

# Constraints for Synthesis Environment
# UPDATE THESE VALUES according to your standard cell library doc
set_load 0.05 [all_outputs]
set_max_fanout 16 [get_designs *]
set_max_transition 0.3 [get_designs *]
