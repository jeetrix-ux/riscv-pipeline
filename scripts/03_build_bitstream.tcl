# 03_build_bitstream.tcl - assemble the demo, synth/place/route soc_top,
# and write a flash-ready bitstream for the Nexys A7-100T.
# Usage: vivado -mode batch -source scripts/03_build_bitstream.tcl
set script_dir [file dirname [file normalize [info script]]]
set repo_root  [file dirname $script_dir]

set part   xc7a100tcsg324-1
set outdir $repo_root/build/soc
file mkdir $outdir

# assemble the demo program; cd so imem's INIT_FILE "demo.hex" resolves
exec python "$repo_root/sw/asm.py" "$repo_root/sw/demo/demo_board.s" \
    -o "$outdir/demo.hex"
cd $outdir

# [list] keeps each path one element despite the space in the repo path
read_verilog [glob $repo_root/rtl/*.v]
read_xdc [list $repo_root/constraints/nexys_a7.xdc]

synth_design -top soc_top -part $part -include_dirs [list $repo_root/rtl]
opt_design
place_design
route_design

report_timing_summary -file timing_summary.rpt
report_utilization    -file utilization.rpt
write_bitstream -force soc_top.bit

set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
puts [format "RESULT: post-route WNS = %.3f ns (core clock 50 MHz); bitstream: %s/soc_top.bit" \
      $wns $outdir]
