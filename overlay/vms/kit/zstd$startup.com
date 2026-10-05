$! ZSTD$STARTUP.COM - system startup for Zstandard (zstd) on OpenVMS
$!
$! Installed by PCSI into SYS$STARTUP.  Defines the system logical name
$! ZSTD$ROOT, pointing at the installed [ZSTD] directory.  To run it at every
$! boot, add this line to SYS$MANAGER:SYSTARTUP_VMS.COM:
$!
$!     $ @SYS$STARTUP:ZSTD$STARTUP.COM
$!
$! P1 = "INSTALL": also print the post-installation tasks (PCSI runs it so).
$! P1 = "REMOVE":  deassign ZSTD$ROOT instead (PCSI runs it so at removal).
$!
$! Users then define the commands with
$!     $ @ZSTD$ROOT:[000000]ZSTD$SETUP.COM
$!
$ set noon
$ mode = f$edit(p1, "UPCASE")
$ if mode .eqs. "REMOVE"
$ then
$   if f$trnlnm("ZSTD$ROOT", "LNM$SYSTEM_TABLE") .nes. "" then -
        deassign/system/executive_mode ZSTD$ROOT
$   exit 1
$ endif
$!
$! This procedure sits in <destination>[SYS$STARTUP]; the product is in
$! <destination>[ZSTD].  Rooted logicals need the physical form:
$! DKA0:[SYS0.SYSCOMMON.SYS$STARTUP] -> DKA0:[SYS0.SYSCOMMON.ZSTD.]
$ proc = f$environment("PROCEDURE")
$ dev = f$parse(proc,,,"DEVICE","NO_CONCEAL")
$ dir = f$edit(f$parse(proc,,,"DIRECTORY","NO_CONCEAL"), "UPCASE") - "]["
$ root = dir - "SYS$STARTUP]" + "ZSTD.]"
$ if root .eqs. dir + "ZSTD.]"
$ then
$   write sys$error "ZSTD$STARTUP: expected to be in a [SYS$STARTUP] directory, not ''dir'"
$   exit 44
$ endif
$ root = root - ".000000"
$ define/system/executive_mode/translation_attributes=concealed ZSTD$ROOT 'dev''root'
$ if f$search("ZSTD$ROOT:[BIN]ZSTD.EXE") .eqs. ""
$ then
$   write sys$error "ZSTD$STARTUP: ZSTD.EXE not found under ''dev'''root'"
$   exit 44
$ endif
$ if mode .nes. "INSTALL" then exit 1
$ say = "write sys$output"
$ say ""
$ say "    Post-installation tasks for Zstandard (zstd)"
$ say ""
$ say "    At system startup: to define ZSTD$ROOT at every boot, add this line to"
$ say "    SYS$MANAGER:SYSTARTUP_VMS.COM:"
$ say "    $ @SYS$STARTUP:ZSTD$STARTUP.COM"
$ say "    For each user: to define the commands, add this line to LOGIN.COM:"
$ say "    $ @ZSTD$ROOT:[000000]ZSTD$SETUP.COM"
$ say ""
$ say "    PRODUCT REMOVE ZSTD removes the product and deassigns ZSTD$ROOT."
$ say ""
$ exit 1
