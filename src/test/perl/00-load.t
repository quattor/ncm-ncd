# -*- mode: cperl -*-
use strict;
use warnings;
use Test::More;
use File::Find;
use Test::Quattor;


my @mods = qw(NCM::Check NCM::HLConfig NCM::Component NCD::ComponentProxy NCD::ComponentProxyList);

plan tests => scalar(@mods);

foreach my $m (@mods) {
    use_ok($m);
}
