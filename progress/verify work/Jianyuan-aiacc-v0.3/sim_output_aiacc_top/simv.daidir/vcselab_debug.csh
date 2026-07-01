#!/bin/csh -f

cd /datahdd/qinglongv200/xuedong/AIACC/Hongjun-main/aiacc/cells/A_Integration/sim_output_aiacc_top

#This ENV is used to avoid overriding current script in next vcselab run 
setenv SNPS_VCSELAB_SCRIPT_NO_OVERRIDE  1

/tools/synopsys/vcs/T-2022.06/linux64/bin/vcselab $* \
    -o \
    simv \
    -nobanner \

cd -

