#!/usr/bin/perl -w

use strict;
use warnings;

sub print_usage() {
	print 	"rename.pl - Recursively renames files to the name of the directory they live in\n\n".
		"\t-v, --version\t\tDisplay version information\n"
}

print_usage();
