#!/usr/bin/perl
# Webmin install_check.pl convention is intentionally inverted compared with
# normal shell success codes: a non-zero exit status means that the module is
# installed/usable and should be shown in the normal menu.  Runtime command
# paths remain configurable, so the module itself is always usable on Linux.
exit 1;
