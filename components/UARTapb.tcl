# Exporting core UARTapb to TCL
# Exporting Create design command for core UARTapb
create_and_configure_core -core_vlnv {Actel:DirectCore:CoreUARTapb:5.6.102} -component_name {UARTapb} -params {\
"BAUD_VAL_FRCTN:0"  \
"BAUD_VAL_FRCTN_EN:false"  \
"BAUD_VALUE:1"  \
"FIXEDMODE:0"  \
"PRG_BIT8:0"  \
"PRG_PARITY:0"  \
"RX_FIFO:0"  \
"RX_LEGACY_MODE:0"  \
"TX_FIFO:0"  \
"USE_SOFT_FIFO:0"   }
# Exporting core UARTapb to TCL done
