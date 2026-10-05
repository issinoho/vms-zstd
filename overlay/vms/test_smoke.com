$! TEST_SMOKE.COM - smoke test for the built zstd ([.BIN_<arch>])
$!
$! Usage:  @[.VMS]TEST_SMOKE [bin-directory]
$! P1: where ZSTD.EXE is (default [.BIN_<arch>]; the install check passes
$!     ZSTD$ROOT:[BIN]).
$!
$! Includes upstream's golden files (tests/golden-*): golden-decompression
$! frames decompress, golden-decompression-errors frames are errors, and the
$! golden-compression inputs round-trip.  Files are compared byte by byte
$! with VSI Perl.
$!
$ set noon
$ saved_default = f$environment("DEFAULT")
$ proc = f$environment("PROCEDURE")
$ vmsdir = f$parse(proc,,,"DEVICE") + f$parse(proc,,,"DIRECTORY")
$ set default 'vmsdir'
$ set default [-]
$ top = f$environment("DEFAULT")
$ tests = top - "]" + ".TESTS"
$ arch = f$edit(f$getsyi("ARCH_NAME"), "UPCASE")
$ bin = f$parse("[.BIN_''arch']",,,"DEVICE") + f$parse("[.BIN_''arch']",,,"DIRECTORY")
$ if p1 .nes. "" then bin = p1
$! The library and headers: the tree's install tree, or the kit's (P1 given).
$ inc = f$parse("[.INSTALL_''arch'.INCLUDE]",,,"DEVICE") + f$parse("[.INSTALL_''arch'.INCLUDE]",,,"DIRECTORY")
$ olb = f$parse("[.INSTALL_''arch'.LIB]LIBZSTD.OLB")
$ if p1 .nes. ""
$ then
$   inc = bin - "BIN]" + "INCLUDE]"
$   olb = bin - "BIN]" + "LIB]LIBZSTD.OLB"
$ endif
$ write sys$output "SMOKE: testing ", bin
$ zstd = "$" + bin + "ZSTD.EXE"
$ pass = 0
$ fail = 0
$ perl_setup = f$search("SYS$COMMON:[PERL-5_*]PERL_SETUP.COM")
$ if perl_setup .eqs. ""
$ then
$   write sys$output "SMOKE: VSI Perl not found (SYS$COMMON:[PERL-5_*]PERL_SETUP.COM)"
$   exit 44
$ endif
$ @'perl_setup'
$ if f$search("SMOKE.DIR") .eqs. "" then create/directory [.SMOKE]
$ set default [.SMOKE]
$ set process/parse_style=extended
$ create same.pl
open my $a, '<:raw', $ARGV[0] or exit 2; open my $b, '<:raw', $ARGV[1] or exit 2;
local $/; my $x = <$a>; my $y = <$b>; exit($x eq $y ? 0 : 1);
$!
$! 1. version
$ define/user sys$output out.txt
$ zstd --version
$ search/nooutput out.txt "Zstandard CLI"
$ sev = $severity
$ name = "version"
$ gosub check_success
$!
$! 2. a text file (variable-length records) round trip: its lines survive
$!    (patch 0003)
$ create text.txt
The quick brown fox jumps over the lazy dog.
OpenVMS, IA64 and x86-64.
$ copy/nolog text.txt orig.txt
$ zstd "-q" text.txt
$ sev = $severity
$ if sev .eq. 1 .and. f$search("text.txt.zst") .eqs. "" then sev = 2
$ if sev .eq. 1
$ then
$   zstd "-q" "-t" text.txt.zst
$   sev = $severity
$ endif
$ if sev .eq. 1
$ then
$   delete/nolog text.txt;*
$   zstd "-q" "-d" text.txt.zst
$   sev = $severity
$   if sev .eq. 1
$   then
$     perl same.pl text.txt orig.txt
$     if $status .ne. 1 then sev = 2
$   endif
$ endif
$ name = "text file round trip (-t, -d)"
$ gosub check_success
$!
$! 3. a binary file (the zstd image itself, fixed-length records) round trip
$!    at -19
$ copy/nolog 'bin'ZSTD.EXE bin.dat
$ copy/nolog bin.dat binorig.dat
$ zstd "-q" "-19" "--rm" bin.dat
$ sev = $severity
$ if sev .eq. 1
$ then
$   zstd "-q" "-d" "--rm" bin.dat.zst
$   sev = $severity
$   if sev .eq. 1
$   then
$     perl same.pl bin.dat binorig.dat
$     if $status .ne. 1 then sev = 2
$   endif
$ endif
$ name = "binary file round trip (-19, --rm, -d)"
$ gosub check_success
$!
$! 4. zstd -l lists a file
$ define/user sys$output out.txt
$ zstd "-l" text.txt.zst
$ search/nooutput out.txt "Frames"
$ sev = $severity
$ name = "zstd -l lists a file"
$ gosub check_success
$!
$! 5. upstream's golden-decompression frames decompress
$ bad = 0
$ count = 0
$gd_loop:
$ f = f$search("''tests'.GOLDEN-DECOMPRESSION]*.ZST", 1)
$ if f .eqs. "" then goto gd_done
$ count = count + 1
$ define/user sys$error nla0:
$ zstd "-q" "-t" 'f'
$ if $severity .ne. 1
$ then
$   bad = bad + 1
$   write sys$output "   failed: ", f$parse(f,,,"NAME") + f$parse(f,,,"TYPE")
$ endif
$ goto gd_loop
$gd_done:
$ sev = 1
$ if bad .gt. 0 .or. count .eq. 0 then sev = 2
$ name = "upstream's ''count' golden-decompression frames decompress"
$ gosub check_success
$!
$! 6. upstream's golden-decompression-errors frames are errors
$ bad = 0
$ count = 0
$ge_loop:
$ f = f$search("''tests'.GOLDEN-DECOMPRESSION-ERRORS]*.ZST", 2)
$ if f .eqs. "" then goto ge_done
$ count = count + 1
$ define/user sys$error nla0:
$ zstd "-q" "-t" 'f'
$ s = $severity
$ if s .ne. 2 .and. s .ne. 4
$ then
$   bad = bad + 1
$   write sys$output "   accepted: ", f$parse(f,,,"NAME") + f$parse(f,,,"TYPE"), " (severity ", s, ")"
$ endif
$ goto ge_loop
$ge_done:
$ sev = 1
$ if bad .gt. 0 .or. count .eq. 0 then sev = 2
$ name = "upstream's ''count' golden-decompression-errors frames give errors"
$ gosub check_success
$!
$! 7. upstream's golden-compression inputs round-trip at -1, -3 and -19
$ bad = 0
$ count = 0
$gc_loop:
$ f = f$search("''tests'.GOLDEN-COMPRESSION]*.*", 3)
$ if f .eqs. "" then goto gc_done
$ count = count + 1
$ copy/nolog 'f' gc.dat
$ lev = 1
$gc_level:
$ zstd "-q" "-f" "-''lev'" "-o" gc.zst gc.dat
$ s = $severity
$ if s .eq. 1
$ then
$   zstd "-q" "-f" "-d" "-o" gc.out gc.zst
$   s = $severity
$   if s .eq. 1
$   then
$     perl same.pl gc.out gc.dat
$     if $status .ne. 1 then s = 2
$   endif
$ endif
$ if s .ne. 1
$ then
$   bad = bad + 1
$   write sys$output "   failed: ", f$parse(f,,,"NAME") + f$parse(f,,,"TYPE"), " at -", lev
$ endif
$ if lev .eq. 1
$ then
$   lev = 3
$   goto gc_level
$ endif
$ if lev .eq. 3
$ then
$   lev = 19
$   goto gc_level
$ endif
$ delete/nolog gc.*;*
$ goto gc_loop
$gc_done:
$ sev = 1
$ if bad .gt. 0 .or. count .eq. 0 then sev = 2
$ name = "upstream's ''count' golden-compression inputs round-trip at -1, -3, -19"
$ gosub check_success
$!
$! 8. a program compiled with the default /NAMES links with LIBZSTD.OLB
$!    (zstd.h declares the API /NAMES=(AS_IS,SHORTENED), patch 0001)
$ create ver.c
#include <stdio.h>
#include <string.h>
#include <zstd.h>
int main (void)
{
  char out[256], back[64];
  size_t n = ZSTD_compress (out, sizeof out, "hello, hello, hello", 19, 3);
  if (ZSTD_isError (n)) return 1;
  n = ZSTD_decompress (back, sizeof back, out, n);
  if (ZSTD_isError (n) || n != 19 || memcmp (back, "hello, hello, hello", 19)) return 1;
  printf ("libzstd %s\n", ZSTD_versionString ());
  return 0;
}
$ cc/nolist/include_directory='inc' ver.c
$ link/nomap ver, 'olb'/library
$ define/user sys$output out.txt
$ run ver
$ search/nooutput out.txt "libzstd 1"
$ sev = $severity
$ name = "a program compiled /NAMES=UPPERCASE links with LIBZSTD.OLB"
$ gosub check_success
$!
$! 9. a corrupt file is an error
$ create bad.zst
this is not a zstd frame
$ define/user sys$error nla0:
$ zstd "-q" "-t" bad.zst
$ sev = $severity
$ name = "a corrupt file gives an error status"
$ gosub check_failure
$!
$! 10. a missing file is an error
$ define/user sys$error nla0:
$ zstd "-q" "-d" nonexistent.zst
$ sev = $severity
$ name = "a missing file gives an error status"
$ gosub check_failure
$!
$ write sys$output "SMOKE: ''pass' passed, ''fail' failed"
$ delete/nolog *.*;*
$ set default [-]
$ set file/protection=o:rwed SMOKE.DIR
$ delete/nolog SMOKE.DIR;
$ set default 'saved_default'
$ if fail .eq. 0 then exit 1
$ exit 44
$!
$check_success:
$ if sev .eq. 1
$ then
$   pass = pass + 1
$   write sys$output "PASS: ", name
$ else
$   fail = fail + 1
$   write sys$output "FAIL: ", name, " (severity ", sev, ")"
$   if f$search("out.txt") .nes. ""
$   then
$     write sys$output "   output was:"
$     type out.txt;0
$   endif
$ endif
$ return
$!
$check_failure:
$ if sev .eq. 2 .or. sev .eq. 4
$ then
$   pass = pass + 1
$   write sys$output "PASS: ", name
$ else
$   fail = fail + 1
$   write sys$output "FAIL: ", name, " (severity ", sev, ", expected an error)"
$ endif
$ return
