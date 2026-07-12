# 01_create_project.tcl - create the Vivado project for the RV32I core.
# Usage: vivado -mode batch -source scripts/01_create_project.tcl
set script_dir [file dirname [file normalize [info script]]]
set repo_root  [file dirname $script_dir]

set part xc7a100tcsg324-1   ;# Nexys A7-100T
create_project riscv_pipeline $repo_root/vivado_proj -part $part -force

set_property target_language Verilog [current_project]

add_files [glob $repo_root/rtl/*.v]
add_files -fileset sim_1 [glob $repo_root/sim/*.v]
# [list] keeps the path intact: add_files takes a list, and a bare path
# containing a space (this repo dir does) would split into two entries
add_files -fileset constrs_1 [list $repo_root/constraints/nexys_a7.xdc]

# rtl/ holds riscv_defs.vh, pulled in via `include
set_property include_dirs [list $repo_root/rtl] [current_fileset]
set_property include_dirs [list $repo_root/rtl] [get_filesets sim_1]

set_property top core_top    [current_fileset]
set_property top tb_core_top [get_filesets sim_1]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

# Note: command-line simulation is driven by scripts/run_sim.ps1, which
# assembles the test program and stages it as program.hex/expected.hex in
# the simulation directory. To simulate from the GUI, assemble first and
# copy those two files into the xsim run directory.

puts "project created: $repo_root/vivado_proj/riscv_pipeline.xpr"
