$! VMS_INSTALLCHECK.COM <tree-dir-name> - install the ZSTD kit, verify, smoke-test
$! the installed image, then remove it.  Changes the system while it runs (PCSI
$! database, SYS$COMMON:[ZSTD], system logical ZSTD$ROOT); leaves it as it was.
$ set noon
$ arch = f$edit(f$getsyi("ARCH_NAME"), "UPCASE")
$ base = "I64VMS"
$ if arch .eqs. "X86_64" then base = "X86VMS"
$ tree = f$environment("DEFAULT") - "]" + "." + p1 + "]"
$ kitdir = tree - "]" + ".KIT_''arch']"
$ write sys$output "=== INSTALL from ", kitdir
$ product install ZSTD /producer=ISSINOHO /base_system='base' /source='kitdir' /options=noconfirm /log
$ write sys$output "=== install status ", $status
$ product show product ZSTD /producer=ISSINOHO
$ write sys$output "=== VERIFY"
$ write sys$output "startup procedure: [", f$search("SYS$STARTUP:ZSTD$STARTUP.COM"), "]"
$ show logical ZSTD$ROOT
$ directory/nohead/notrail ZSTD$ROOT:[000000...]*.*
$ @ZSTD$ROOT:[000000]ZSTD$SETUP.COM
$ show symbol zstd
$ zstd --version
$ write sys$output "=== SMOKE TEST on installed image"
$ smoke = tree - "]" + ".VMS]TEST_SMOKE.COM"
$ @'smoke' ZSTD$ROOT:[BIN]
$ write sys$output "=== REMOVE"
$ product remove ZSTD /producer=ISSINOHO /options=noconfirm /log
$ write sys$output "=== remove status ", $status
$ write sys$output "ZSTD$ROOT after removal: [", f$trnlnm("ZSTD$ROOT"), "]"
$ write sys$output "files after removal: [", f$search("SYS$COMMON:[ZSTD...]*.*"), "]"
$ write sys$output "startup after removal: [", f$search("SYS$STARTUP:ZSTD$STARTUP.COM"), "]"
$ product show product ZSTD /producer=ISSINOHO
$ delete/symbol/global zstd
$ delete/symbol/global unzstd
$ delete/symbol/global zstdcat
