#!/usr/bin/perl
use strict;
use warnings;
use DynaLoader;

my ($library, $symbol) = @ARGV;
die "usage: artwork-bridge.pl <library> <symbol>\n" unless $library && $symbol;

my $handle = DynaLoader::dl_load_file($library, 0)
    or die "could not load artwork bridge\n";
my $address = DynaLoader::dl_find_symbol($handle, $symbol)
    or die "could not find artwork bridge entry point\n";
my $function = DynaLoader::dl_install_xsub("main::$symbol", $address);
&$function();
