# 02_synth_ooc.tcl - out-of-context synthesis of core_top + timing/area reports.
# Usage: vivado -mode batch -source scripts/02_synth_ooc.tcl
set script_dir [file dirname [file normalize [info script]]]
set repo_root  [file dirname $script_dir]

set part   xc7a100tcsg324-1   ;# Nexys A7-100T
set period 10.000             ;# 100 MHz target
set outdir $repo_root/build/synth
file mkdir $outdir

# [glob] returns a proper list, so the space in the repo path is safe
read_verilog [glob $repo_root/rtl/*.v]

synth_design -top core_top -part $part -mode out_of_context \
    -include_dirs [list $repo_root/rtl]

create_clock -period $period -name clk [get_ports clk]

report_timing_summary -file $outdir/timing_summary.rpt
report_timing -sort_by slack -max_paths 3 -file $outdir/critical_paths.rpt
report_utilization -file $outdir/utilization.rpt

# one-line verdict for the console
set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
set fmax [expr {1000.0 / ($period - $wns)}]
puts [format "RESULT: WNS = %.3f ns at %.0f MHz target => Fmax ~ %.1f MHz" \
      $wns [expr {1000.0 / $period}] $fmax]
