# Exporting core TxPLL to TCL
# Exporting Create design command for core TxPLL
create_and_configure_core -core_vlnv {Actel:SgCore:PF_TX_PLL:2.0.202} -component_name {TxPLL} -params {\
"CORE:PF_TX_PLL"  \
"INIT:0x0"  \
"TxPLL_AUX_LOW_SEL:true"  \
"TxPLL_AUX_OUT:125"  \
"TxPLL_BANDWIDTH:Low"  \
"TxPLL_CLK_125_EN:false"  \
"TxPLL_DYNAMIC_RECONFIG_INTERFACE_EN:false"  \
"TxPLL_EXT_WAVE_SEL:0"  \
"TxPLL_FAB_LOCK_EN:false"  \
"TxPLL_FAB_REF:200"  \
"TxPLL_JITTER_MODE_SEL:10G SyncE 32Bit"  \
"TxPLL_MODE:NORMAL"  \
"TxPLL_OUT:3000"  \
"TxPLL_REF:100"  \
"TxPLL_SOURCE:DEDICATED"  \
"TxPLL_SSM_DEPTH:0"  \
"TxPLL_SSM_DIVVAL:1"  \
"TxPLL_SSM_DOWN_SPREAD:false"  \
"TxPLL_SSM_FREQ:64"  \
"TxPLL_SSM_RAND_PATTERN:0"  \
"VCOFREQUENCY:1600"   }
# Exporting core TxPLL to TCL done