# -*- mode: cperl -*-
use strict;
use warnings;

BEGIN {
    # Ignore the ncm namespace loaded by Test::Quattor
    use Test::Quattor::Namespace;
    $Test::Quattor::Namespace::ignore->{ncm} = 1;
}

use Test::More;
use File::Find;
use Test::Quattor;

BEGIN {
  use CAF::Application;
  our $this_app = CAF::Application->new('app');
  $this_app->{CONFIG}->define("noaction");
  $this_app->{CONFIG}->set('noaction', 1);
  $this_app->{CONFIG}->define("template-path");
  $this_app->{CONFIG}->set('template-path', "doesnotexist");
}


my @mods = qw(NCM::Check NCM::Component NCD::ComponentProxy NCD::ComponentProxyList);

plan tests => scalar(@mods);

foreach my $m (@mods) {
    use_ok($m);
}
