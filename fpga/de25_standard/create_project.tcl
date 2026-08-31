set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir .. ..]]
set project_name de25_standard_ai_accelerator

if {![info exists ::env(DE25_DEVICE)] || $::env(DE25_DEVICE) eq ""} {
  error "Set DE25_DEVICE to the exact Quartus device string from the Terasic baseline project for your board revision."
}
if {![info exists ::env(DE25_PROJECT_DIR)] || $::env(DE25_PROJECT_DIR) eq ""} {
  error "Set DE25_PROJECT_DIR to an isolated Quartus build directory."
}
if {![info exists ::env(DE25_RESET_RELEASE_IP)]
    || ![file exists $::env(DE25_RESET_RELEASE_IP)]} {
  error "Generate the Agilex 5 Reset Release IP and set DE25_RESET_RELEASE_IP."
}

set project_dir [file normalize $::env(DE25_PROJECT_DIR)]

file mkdir $project_dir
project_new [file join $project_dir $project_name] -overwrite

set_global_assignment -name FAMILY "Agilex 5"
set_global_assignment -name DEVICE $::env(DE25_DEVICE)
set_global_assignment -name TOP_LEVEL_ENTITY de25_standard_selftest_top
set_global_assignment -name VERILOG_MACRO "SYNTHESIS"
set_global_assignment -name SYSTEMVERILOG_FILE [file join $repo_root rtl ai_accel_pkg.sv]
set_global_assignment -name SYSTEMVERILOG_FILE [file join $repo_root rtl mac_pe.sv]
set_global_assignment -name SYSTEMVERILOG_FILE [file join $repo_root rtl mac_array_4x4.sv]
set_global_assignment -name SYSTEMVERILOG_FILE [file join $repo_root rtl scratchpad_sram.sv]
set_global_assignment -name SYSTEMVERILOG_FILE [file join $repo_root rtl multi_read_scratchpad.sv]
set_global_assignment -name SYSTEMVERILOG_FILE [file join $repo_root rtl parallel_operand_feeder.sv]
set_global_assignment -name SYSTEMVERILOG_FILE [file join $repo_root rtl requant_relu.sv]
set_global_assignment -name SYSTEMVERILOG_FILE [file join $repo_root rtl output_tile_writer.sv]
set_global_assignment -name SYSTEMVERILOG_FILE [file join $repo_root rtl compute_controller.sv]
set_global_assignment -name SYSTEMVERILOG_FILE [file join $repo_root rtl simple_dma.sv]
set_global_assignment -name SYSTEMVERILOG_FILE [file join $repo_root rtl perf_counters.sv]
set_global_assignment -name SYSTEMVERILOG_FILE [file join $repo_root rtl accel_status_irq.sv]
set_global_assignment -name SYSTEMVERILOG_FILE [file join $repo_root rtl apb_accel_regs.sv]
set_global_assignment -name SYSTEMVERILOG_FILE [file join $repo_root rtl accel_controller.sv]
set_global_assignment -name SYSTEMVERILOG_FILE [file join $repo_root rtl ai_accelerator_top.sv]
set_global_assignment -name SYSTEMVERILOG_FILE [file join $script_dir rtl de25_standard_selftest_top.sv]
set_global_assignment -name IP_FILE [file normalize $::env(DE25_RESET_RELEASE_IP)]
set_global_assignment -name SDC_FILE [file join $script_dir constraints de25_standard_selftest.sdc]

set pin_file [file join $script_dir constraints de25_standard_revision_pins.qsf]
if {[file exists $pin_file]} {
  source $pin_file
} else {
  post_message -type warning "No revision-specific pin file found at $pin_file. Analysis and synthesis can run, but the bitstream must not be programmed until official Terasic pin assignments are added."
}

export_assignments
project_close
