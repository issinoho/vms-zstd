$! ZSTD$SETUP.COM - define the Zstandard (zstd) commands for a user
$!
$! Add to LOGIN.COM (or SYS$MANAGER:SYLOGIN.COM for everyone):
$!     $ @ZSTD$ROOT:[000000]ZSTD$SETUP.COM
$!
$! Quote upper-case options, or SET PROCESS/PARSE_STYLE=EXTENDED: traditional DCL
$! parsing changes the case of unquoted arguments; batch jobs use the traditional style.
$!
$ if f$trnlnm("ZSTD$ROOT") .eqs. ""
$ then
$   write sys$error "ZSTD$SETUP: ZSTD$ROOT is not defined; run ZSTD$STARTUP.COM first"
$   exit 44
$ endif
$ zstd    :== $ZSTD$ROOT:[BIN]ZSTD.EXE
$ unzstd  :== "$ZSTD$ROOT:[BIN]ZSTD.EXE -d"
$ zstdcat :== "$ZSTD$ROOT:[BIN]ZSTD.EXE -dc"
$ exit 1
