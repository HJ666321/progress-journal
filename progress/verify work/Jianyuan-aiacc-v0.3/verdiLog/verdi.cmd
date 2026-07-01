simSetSimulator "-vcssv" -exec "./sim_output_aiacc_top/simv" -args
debImport "-dbdir" "./sim_output_aiacc_top/simv.daidir/"
verdiSetActWin -dock widgetDock_MTB_SOURCE_TAB_1
wvCreateWindow
wvSetPosition -win $_nWave2 {("G1" 0)}
wvOpenFile -win $_nWave2 \
           {/datahdd/qinglongv200/xuedong/AIACC/Hongjun-main/aiacc/cells/A_Integration/sim_output_aiacc_top/tb_aiacc_top.fsdb}
wvRestoreSignal -win $_nWave2 \
           "/datahdd/qinglongv200/xuedong/AIACC/Hongjun-main/aiacc/cells/A_Integration/signal_aiacc.rc" \
           -overWriteAutoAlias on -appendSignals on
wvZoomOut -win $_nWave2
wvZoomOut -win $_nWave2
wvZoomOut -win $_nWave2
wvZoomOut -win $_nWave2
wvZoomOut -win $_nWave2
wvZoomOut -win $_nWave2
wvZoomOut -win $_nWave2
wvZoomOut -win $_nWave2
wvGoToGroup -win $_nWave2 "fpadd"
wvZoomOut -win $_nWave2
wvZoomOut -win $_nWave2
wvZoom -win $_nWave2 915431.981352 1145928.578089
wvSelectSignal -win $_nWave2 {( "fpadd" 9 )} 
wvSelectSignal -win $_nWave2 {( "fpadd" 8 )} 
wvZoomOut -win $_nWave2
wvZoom -win $_nWave2 923759.946968 1027725.195147
wvZoomOut -win $_nWave2
wvZoomOut -win $_nWave2
wvZoom -win $_nWave2 929212.669775 1022999.502048
wvZoomOut -win $_nWave2
wvSetCursor -win $_nWave2 974466.455976 -snap {("fpadd" 8)}
wvSetCursor -win $_nWave2 945390.351798 -snap {("fpadd" 2)}
wvZoomOut -win $_nWave2
wvZoomOut -win $_nWave2
wvZoomOut -win $_nWave2
wvZoomOut -win $_nWave2
wvZoomOut -win $_nWave2
wvZoom -win $_nWave2 915431.981352 1081476.923077
wvSetCursor -win $_nWave2 964684.239707 -snap {("fpadd" 1)}
wvSetCursor -win $_nWave2 934591.013089 -snap {("fpadd" 1)}
wvSetCursor -win $_nWave2 944364.054531 -snap {("fpadd" 1)}
wvSetCursor -win $_nWave2 953943.570400 -snap {("fpadd" 1)}
wvSetCursor -win $_nWave2 964587.476921 -snap {("fpadd" 1)}
wvSetCursor -win $_nWave2 975811.960161 -snap {("fpadd" 1)}
wvSelectSignal -win $_nWave2 {( "fpadd" 8 )} 
wvSelectSignal -win $_nWave2 {( "fpadd" 9 )} 
wvSelectSignal -win $_nWave2 {( "fpadd" 10 )} 
wvSelectSignal -win $_nWave2 {( "fpadd" 11 )} 
wvSetCursor -win $_nWave2 935074.827022 -snap {("fpadd" 5)}
wvSetCursor -win $_nWave2 965071.290854 -snap {("fpadd" 6)}
wvSetCursor -win $_nWave2 935365.115382 -snap {("fpadd" 5)}
srcHBSelect "tb_aiacc_top" -win $_nTrace1
srcSetScope "tb_aiacc_top" -delim "." -win $_nTrace1
srcHBSelect "tb_aiacc_top" -win $_nTrace1
verdiSetActWin -dock widgetDock_<Inst._Tree>
srcHBSelect "tb_aiacc_top.dut" -win $_nTrace1
srcSetScope "tb_aiacc_top.dut" -delim "." -win $_nTrace1
srcHBSelect "tb_aiacc_top.dut" -win $_nTrace1
srcHBSelect "tb_aiacc_top.dut.u_smi_iq_inttofp" -win $_nTrace1
srcHBSelect "tb_aiacc_top.dut.u_smc" -win $_nTrace1
srcSetScope "tb_aiacc_top.dut.u_smc" -delim "." -win $_nTrace1
srcHBSelect "tb_aiacc_top.dut.u_smc" -win $_nTrace1
srcHBSelect "tb_aiacc_top.dut.u_smc.u_fpadd" -win $_nTrace1
srcSetScope "tb_aiacc_top.dut.u_smc.u_fpadd" -delim "." -win $_nTrace1
srcHBSelect "tb_aiacc_top.dut.u_smc.u_fpadd" -win $_nTrace1
srcDeselectAll -win $_nTrace1
srcSelect -signal "w_add_sub" -line 86 -pos 1 -win $_nTrace1
verdiSetActWin -dock widgetDock_MTB_SOURCE_TAB_1
srcDeselectAll -win $_nTrace1
srcSelect -signal "i_cru_fpadd\[4\]" -line 86 -pos 1 -win $_nTrace1
wvSelectSignal -win $_nWave2 {( "fpadd" 3 )} 
verdiSetActWin -win $_nWave2
wvSelectSignal -win $_nWave2 {( "fpadd" 6 )} 
srcDeselectAll -win $_nTrace1
srcSelect -signal "i_rounding_mode" -line 71 -pos 1 -win $_nTrace1
srcDeselectAll -win $_nTrace1
srcSelect -signal "i_cru_fpadd" -line 70 -pos 1 -win $_nTrace1
verdiSetActWin -dock widgetDock_MTB_SOURCE_TAB_1
wvSelectSignal -win $_nWave2 {( "fpadd" 6 )} 
verdiSetActWin -win $_nWave2
wvScrollDown -win $_nWave2 0
wvSetPosition -win $_nWave2 {("fpadd" 5)}
wvSelectSignal -win $_nWave2 {( "fpadd" 5 )} 
wvSelectSignal -win $_nWave2 {( "fpadd" 6 )} 
wvCut -win $_nWave2
wvSetPosition -win $_nWave2 {("fpadd" 5)}
srcDeselectAll -win $_nTrace1
srcDeselectAll -win $_nTrace1
srcSelect -signal "i_cru_fpadd" -line 70 -pos 1 -win $_nTrace1
verdiSetActWin -dock widgetDock_MTB_SOURCE_TAB_1
srcAddSelectedToWave -clipboard -win $_nTrace1
wvDrop -win $_nWave2
wvSelectSignal -win $_nWave2 {( "fpadd" 11 )} 
verdiSetActWin -win $_nWave2
wvCut -win $_nWave2
wvSetPosition -win $_nWave2 {("fpadd" 6)}
wvSetPosition -win $_nWave2 {("fpadd" 10)}
srcDeselectAll -win $_nTrace1
srcSelect -signal "o_cru_fpadd_o" -line 79 -pos 1 -win $_nTrace1
srcAddSelectedToWave -clipboard -win $_nTrace1
wvDrop -win $_nWave2
verdiSetActWin -dock widgetDock_MTB_SOURCE_TAB_1
verdiSetActWin -win $_nWave2
wvSaveSignal -win $_nWave2 \
           "/datahdd/qinglongv200/xuedong/AIACC/Hongjun-main/aiacc/cells/A_Integration/signal_aiacc.rc"
srcDeselectAll -win $_nTrace1
verdiSetActWin -dock widgetDock_MTB_SOURCE_TAB_1
wvScrollDown -win $_nWave2 1
wvScrollDown -win $_nWave2 1
verdiSetActWin -win $_nWave2
wvScrollDown -win $_nWave2 1
wvScrollDown -win $_nWave2 1
wvScrollDown -win $_nWave2 1
wvScrollDown -win $_nWave2 1
wvScrollDown -win $_nWave2 1
wvScrollDown -win $_nWave2 1
wvScrollDown -win $_nWave2 1
wvScrollDown -win $_nWave2 1
wvScrollDown -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvZoomOut -win $_nWave2
wvZoomOut -win $_nWave2
wvZoomOut -win $_nWave2
wvZoomOut -win $_nWave2
wvZoomOut -win $_nWave2
wvZoomOut -win $_nWave2
wvScrollDown -win $_nWave2 1
wvScrollDown -win $_nWave2 1
wvScrollDown -win $_nWave2 1
wvScrollDown -win $_nWave2 1
wvScrollDown -win $_nWave2 1
wvScrollDown -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollDown -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollDown -win $_nWave2 0
wvScrollDown -win $_nWave2 0
wvScrollDown -win $_nWave2 0
wvScrollDown -win $_nWave2 0
wvScrollDown -win $_nWave2 0
wvScrollDown -win $_nWave2 0
wvScrollDown -win $_nWave2 1
wvScrollDown -win $_nWave2 1
wvScrollDown -win $_nWave2 1
wvScrollDown -win $_nWave2 1
wvScrollDown -win $_nWave2 1
wvScrollDown -win $_nWave2 1
wvScrollDown -win $_nWave2 1
wvScrollDown -win $_nWave2 1
wvScrollDown -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollDown -win $_nWave2 0
wvScrollDown -win $_nWave2 0
wvScrollDown -win $_nWave2 0
wvScrollDown -win $_nWave2 0
wvZoom -win $_nWave2 873920.745921 1209287.832168
wvGoToGroup -win $_nWave2 "UR_wr_ram"
wvSetCursor -win $_nWave2 1085577.246157 -snap {("UR_wr_ram" 1)}
wvZoomOut -win $_nWave2
wvZoomOut -win $_nWave2
wvZoomOut -win $_nWave2
wvSelectSignal -win $_nWave2 {( "UR_wr_ram" 1 )} 
wvSelectSignal -win $_nWave2 {( "UR_wr_ram" 1 2 )} 
wvSelectSignal -win $_nWave2 {( "UR_wr_ram" 1 2 3 )} 
wvSelectSignal -win $_nWave2 {( "UR_wr_ram" 1 2 3 4 )} 
wvSelectSignal -win $_nWave2 {( "UR_wr_ram" 1 2 3 4 5 )} 
wvZoomOut -win $_nWave2
wvZoomOut -win $_nWave2
wvZoomOut -win $_nWave2
wvZoomOut -win $_nWave2
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollDown -win $_nWave2 1
wvScrollDown -win $_nWave2 1
wvScrollDown -win $_nWave2 1
wvScrollDown -win $_nWave2 1
wvScrollDown -win $_nWave2 1
wvScrollDown -win $_nWave2 1
wvScrollDown -win $_nWave2 1
wvScrollDown -win $_nWave2 1
wvScrollDown -win $_nWave2 1
wvScrollDown -win $_nWave2 1
wvSelectSignal -win $_nWave2 {( "UR_wr_ram" 20 )} 
wvSelectSignal -win $_nWave2 {( "UR_wr_ram" 19 20 )} 
wvSelectSignal -win $_nWave2 {( "UR_wr_ram" 18 19 20 )} 
wvSelectSignal -win $_nWave2 {( "UR_wr_ram" 17 18 19 20 )} 
wvSelectSignal -win $_nWave2 {( "UR_wr_ram" 16 17 18 19 20 )} 
wvScrollDown -win $_nWave2 1
wvScrollDown -win $_nWave2 1
wvScrollDown -win $_nWave2 1
wvScrollDown -win $_nWave2 1
wvScrollDown -win $_nWave2 1
wvScrollDown -win $_nWave2 1
wvScrollDown -win $_nWave2 1
wvScrollDown -win $_nWave2 1
wvScrollDown -win $_nWave2 1
wvScrollDown -win $_nWave2 1
wvScrollDown -win $_nWave2 1
wvScrollDown -win $_nWave2 1
wvScrollDown -win $_nWave2 1
wvScrollDown -win $_nWave2 1
wvScrollDown -win $_nWave2 1
wvScrollDown -win $_nWave2 1
wvScrollDown -win $_nWave2 1
wvScrollDown -win $_nWave2 1
wvScrollDown -win $_nWave2 1
wvScrollDown -win $_nWave2 1
wvScrollDown -win $_nWave2 1
wvScrollDown -win $_nWave2 1
wvScrollDown -win $_nWave2 1
wvScrollDown -win $_nWave2 1
wvScrollDown -win $_nWave2 1
wvScrollDown -win $_nWave2 1
wvScrollDown -win $_nWave2 1
wvScrollDown -win $_nWave2 1
wvScrollDown -win $_nWave2 1
wvScrollDown -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvZoom -win $_nWave2 1063998.508159 1155760.186480
wvSelectSignal -win $_nWave2 {( "UR_wr_ram" 1 )} 
wvSelectSignal -win $_nWave2 {( "UR_wr_ram" 2 )} 
wvSelectSignal -win $_nWave2 {( "UR_wr_ram" 3 )} 
wvSelectSignal -win $_nWave2 {( "UR_wr_ram" 4 )} 
wvSelectSignal -win $_nWave2 {( "UR_wr_ram" 5 )} 
wvSelectSignal -win $_nWave2 {( "UR_wr_ram" 4 )} 
wvZoomOut -win $_nWave2
wvZoomOut -win $_nWave2
wvZoomOut -win $_nWave2
wvZoomOut -win $_nWave2
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvSetCursor -win $_nWave2 928494.957537 -snap {("UR_rd_ram_G3" 8)}
wvSelectSignal -win $_nWave2 {( "UR_rd_ram_G3" 8 )} 
wvSetCursor -win $_nWave2 913949.982884 -snap {("UR_rd_ram_G3" 6)}
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollUp -win $_nWave2 1
wvScrollDown -win $_nWave2 0
wvScrollDown -win $_nWave2 0
wvScrollDown -win $_nWave2 0
wvScrollDown -win $_nWave2 0
wvScrollDown -win $_nWave2 0
wvScrollDown -win $_nWave2 0
wvSetCursor -win $_nWave2 1381100.345249 -snap {("fpadd" 8)}
wvSelectSignal -win $_nWave2 {( "fpadd" 8 )} 
wvZoom -win $_nWave2 1035443.300569 1087634.091969
wvSetCursor -win $_nWave2 1054877.983379 -snap {("fpadd" 6)}
wvZoomOut -win $_nWave2
wvZoomOut -win $_nWave2
wvZoomOut -win $_nWave2
wvSetCursor -win $_nWave2 1004359.973756 -snap {("fpadd" 6)}
wvSetCursor -win $_nWave2 1013119.267418 -snap {("fpadd" 6)}
wvSetCursor -win $_nWave2 1054969.226023 -snap {("fpadd" 6)}
wvSetCursor -win $_nWave2 1064215.147110 -snap {("fpadd" 8)}
wvSetCursor -win $_nWave2 994384.111531 -snap {("fpadd" 8)}
wvSetCursor -win $_nWave2 1053995.971171 -snap {("fpadd" 8)}
wvSetCursor -win $_nWave2 1063971.833397 -snap {("fpadd" 8)}
wvSetCursor -win $_nWave2 1091855.584886 -snap {("fpadd" 11)}
wvSetCursor -win $_nWave2 1056575.096527 -snap {("fpadd" 11)}
wvSetCursor -win $_nWave2 1046550.571559 -snap {("fpadd" 11)}
wvSetCursor -win $_nWave2 1003484.044390 -snap {("fpadd" 6)}
wvSelectSignal -win $_nWave2 {( "fpadd" 10 )} 
wvCut -win $_nWave2
wvSetPosition -win $_nWave2 {("inst_G2" 0)}
wvSetPosition -win $_nWave2 {("fpadd" 10)}
wvSaveSignal -win $_nWave2 \
           "/datahdd/qinglongv200/xuedong/AIACC/Hongjun-main/aiacc/cells/A_Integration/signal_aiacc.rc"
srcDeselectAll -win $_nTrace1
verdiSetActWin -dock widgetDock_MTB_SOURCE_TAB_1
wvScrollDown -win $_nWave2 1
wvScrollDown -win $_nWave2 1
wvScrollDown -win $_nWave2 1
wvScrollDown -win $_nWave2 1
wvScrollDown -win $_nWave2 1
verdiSetActWin -win $_nWave2
wvScrollDown -win $_nWave2 1
wvScrollDown -win $_nWave2 1
wvScrollDown -win $_nWave2 1
wvScrollDown -win $_nWave2 1
wvScrollDown -win $_nWave2 1
wvGoToGroup -win $_nWave2 "UR_wr_ram"
wvSetCursor -win $_nWave2 1084020.883333 -snap {("UR_wr_ram" 3)}
wvSetCursor -win $_nWave2 1084020.883333 -snap {("UR_wr_ram" 2)}
wvSelectSignal -win $_nWave2 {( "UR_wr_ram" 1 )} 
wvSelectSignal -win $_nWave2 {( "UR_wr_ram" 2 )} 
wvSelectSignal -win $_nWave2 {( "UR_wr_ram" 3 )} 
wvSelectSignal -win $_nWave2 {( "UR_wr_ram" 4 )} 
wvSelectSignal -win $_nWave2 {( "UR_wr_ram" 5 )} 
wvSelectSignal -win $_nWave2 {( "UR_wr_ram" 1 )} 
debExit
