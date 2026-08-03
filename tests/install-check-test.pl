#!/usr/bin/env perl
use strict;
use warnings;

my $rc = system($^X, './install_check.pl');
die "install_check.pl failed to execute\n" if ($rc == -1);
my $exit = $rc >> 8;
die "install_check.pl must return non-zero so Webmin lists the module as installed; got $exit\n"
    if ($exit == 0);
print "install-check menu visibility test passed\n";
