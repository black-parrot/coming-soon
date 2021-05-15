# Genesys 2 - xc7k325tffg900-2
# Artix 7   - xc7a200tfbg676-2
set PART $::env(PART)

set BP_TOP_DIR $::env(BP_TOP_DIR)
set BP_COMMON_DIR $::env(BP_COMMON_DIR)
set BP_BE_DIR $::env(BP_BE_DIR)
set BP_FE_DIR $::env(BP_FE_DIR)
set BP_ME_DIR $::env(BP_ME_DIR)
set BASEJUMP_STL_DIR $::env(BASEJUMP_STL_DIR)
set HARDFLOAT_DIR $::env(HARDFLOAT_DIR)

set REPORT_DIR $::env(REPORT_DIR)

set proj_name "blackparrot_test"
set part "xc7z020clg400-1"
create_project -force $proj_name ./$proj_name -part $part

set f [split [string trim [read [open "flist.vcs" r]]] "\n"]
set flist [list ]
set dir_list [list ]
foreach x $f {
  if {![string match "" $x]} {
    # If the item starts with +incdir+, directory files need to be added
    if {[string match "+" [string index $x 0]]} {
      set trimchars "+incdir+"
      set temp [string trimleft $x $trimchars]
      set expanded [subst $temp]
      lappend dir_list $expanded
    } elseif {[string match "*bsg_mem_1rw_sync_mask_write_bit*.v" $x]} {
      # bitmasked memories are incorrectly inferred in Kintex 7 and Ultrascale+ FPGAs, this version maps into lutram correctly
      set replace_hard "$BASEJUMP_STL_DIR/hard/ultrascale_plus/bsg_mem/bsg_mem_1rw_sync_mask_write_bit.v"
      set expanded [subst $replace_hard]
      lappend flist $expanded
      puts $expanded
    } else {
      set expanded [subst $x]
      lappend flist $expanded
    }
  }
}

puts $flist
#set_part $PART
read_verilog -sv $flist
#read_xdc design.xdc

set top_file [list ]
lappend top_file ""

set fileset_obj [get_filesets sources_1]
add_files -fileset $fileset_obj $top_file

set_property top main_top [current_fileset]

synth_design -include_dirs $dir_list -flatten_hierarchy none
#report_utilization -file $REPORT_DIR/hier_util.rpt -hierarchical -hierarchical_percentages
#report_timing_summary -file $REPORT_DIR/timing.rpt
# Rename submodules to avoid name conflicts with unsynth versions
#rename_ref -prefix_all synth_
#write_verilog -force -mode funcsim wrapper_synth.sv

