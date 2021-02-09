#!/bin/bash -l
 
#$ -N bp_gzip_sw_sbmt_default_cfg 
#$ -o /project/risc-v/software/black-parrot/dev-20190501/zazad/bp_zipline/demo/black-parrot/bp_top/syn/bp_gzip_sw_sbmt_task_default_cfg_log
#$ -P risc-v
#$ -l h_rt=48:00:00


module load gcc/9.3.0
module load synopsys/Q-2020.03-SP2
module load  python3

# program name or command and its options and arguments
make -C /project/risc-v/software/black-parrot/dev-20190501/zazad/bp_zipline/demo/black-parrot/bp_top/syn  build_dump.v sim_dump.v  SUITE=spec PROG=164.gzip TAG=gzip_sw_sbm_task_default_cfg
