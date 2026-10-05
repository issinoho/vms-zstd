! DESCRIP.MMS - build Zstandard (zstd) for OpenVMS (IA64, x86-64)
!
! Run via [.VMS]BUILD.COM, which passes ARCH and creates the output
! directories.  zstd has no configure; [.VMS]SOURCES.MMS (tools/
! gen_sources.py) lists the sources zstd's own makefiles use.
!
! Outputs:
!   [.OBJ_<arch>]LIBZSTD.OLB          the library (libzstd)
!   [.BIN_<arch>]ZSTD.EXE             the zstd command
!   [.INSTALL_<arch>.INCLUDE]         ZSTD.H, ZSTD_ERRORS.H, ZDICT.H  (install
!   [.INSTALL_<arch>.LIB]LIBZSTD.OLB  tree used by other ports)

.IFDEF ARCH
.ELSE
ARCH = IA64
.ENDIF

OBJ = [.OBJ_$(ARCH)]
LOBJ = [.OBJ_$(ARCH).LIB]
BIN = [.BIN_$(ARCH)]
INST = [.INSTALL_$(ARCH)

.INCLUDE [.VMS]SOURCES.MMS

! The family's VSI C qualifiers (/NAMES=(AS_IS,SHORTENED); zstd.h declares
! its API so on VMS, patch 0001).  Include directories in Unix form: zstd's
! sources include "../lib/zstd.h" and the like, which VSI C finds only
! relative to such a directory.
!   ZSTD_DISABLE_ASM      no x86-64 assembler (huf_decompress_amd64.S)
!   ZSTD_LEGACY_SUPPORT=5 decode the v0.5-v0.7 formats too (the default)
!   XXH_NAMESPACE=ZSTD_   as lib/libzstd.mk builds it
! No ZSTD_MULTITHREAD: single-threaded, like the family's other ports.
CC = CC
CC_QUAL = /NAMES=(AS_IS,SHORTENED)/FLOAT=IEEE_FLOAT/IEEE_MODE=DENORM_RESULTS-
	/PREFIX_LIBRARY_ENTRIES=ALL_ENTRIES/WARNINGS=(ERRORS=IMPLICITFUNC)/MAIN=POSIX_EXIT/NOLIST
ZSTD_DEFS = _LARGEFILE,_USE_STD_STAT,_POSIX_EXIT,ZSTD_DISABLE_ASM,"ZSTD_LEGACY_SUPPORT=5","XXH_NAMESPACE=ZSTD_"
LIB_CFLAGS = $(CC_QUAL)/INCLUDE_DIRECTORY=("./lib","./lib/common","./lib/legacy")-
	/DEFINE=($(ZSTD_DEFS))
CFLAGS = $(CC_QUAL)/INCLUDE_DIRECTORY=("./programs","./lib","./lib/common","./vms")-
	/DEFINE=($(ZSTD_DEFS))

LIB = $(OBJ)LIBZSTD.OLB
VMS_OBJS = $(OBJ)vms_exit.OBJ, $(OBJ)vms_crtl_init.OBJ

ALL : $(LIB), $(BIN)ZSTD.EXE, INSTALL_TREE
	@ CONTINUE

INSTALL_TREE : $(INST).LIB]LIBZSTD.OLB, $(INST).INCLUDE]ZSTD.H, -
	$(INST).INCLUDE]ZSTD_ERRORS.H, $(INST).INCLUDE]ZDICT.H
	@ CONTINUE

! "-": LIBRARY and LINK end with a warning status for modules compiled with
! warnings; tools/build.sh fails the build on real errors.
$(LIB) : $(LIB_OBJS)
	IF F$SEARCH("$(MMS$TARGET)") .EQS. "" THEN LIBRARY/CREATE/OBJECT $(MMS$TARGET)
	- LIBRARY/REPLACE/OBJECT $(MMS$TARGET) $(LOBJ)*.OBJ

$(BIN)ZSTD.EXE : $(CLI_OBJS), $(VMS_OBJS), $(LIB)
	- LINK/EXECUTABLE=$(MMS$TARGET)/MAP=$(OBJ)ZSTD.MAP $(CLI_OBJS), $(VMS_OBJS), $(LIB)/LIBRARY

$(INST).LIB]LIBZSTD.OLB : $(LIB)
	COPY $(MMS$SOURCE) $(MMS$TARGET)
$(INST).INCLUDE]ZSTD.H : [.LIB]zstd.h
	COPY $(MMS$SOURCE) $(MMS$TARGET)
$(INST).INCLUDE]ZSTD_ERRORS.H : [.LIB]zstd_errors.h
	COPY $(MMS$SOURCE) $(MMS$TARGET)
$(INST).INCLUDE]ZDICT.H : [.LIB]zdict.h
	COPY $(MMS$SOURCE) $(MMS$TARGET)

$(OBJ)vms_exit.OBJ : [.VMS]vms_exit.c
	- $(CC) $(CFLAGS) /OBJECT=$(MMS$TARGET) $(MMS$SOURCE)
$(OBJ)vms_crtl_init.OBJ : [.VMS]vms_crtl_init.c
	- $(CC) $(CFLAGS) /OBJECT=$(MMS$TARGET) $(MMS$SOURCE)

CLEAN :
	IF F$SEARCH("$(LOBJ)*.*") .NES. "" THEN DELETE/NOLOG $(LOBJ)*.*;*
	IF F$SEARCH("$(OBJ)*.*") .NES. "" THEN DELETE/NOLOG $(OBJ)*.*;*
	IF F$SEARCH("$(BIN)*.*") .NES. "" THEN DELETE/NOLOG $(BIN)*.*;*
