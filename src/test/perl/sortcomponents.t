# -*- mode: cperl -*-
use strict;
use warnings;
use Test::More;
use Test::Quattor qw(cmplist);
use NCD::ComponentProxyList;
use NCD::ComponentProxy;
use CAF::Application;

our $this_app = CAF::Application->new('app');
$this_app->{CONFIG}->define("autodeps");
$this_app->{CONFIG}->define("nodeps");
$this_app->{CONFIG}->set('nodeps', 0);

my $cfg = get_config_for_profile('cmplist');

my @unsorted = (NCD::ComponentProxy->new('second', $cfg),
		NCD::ComponentProxy->new('third', $cfg),
		NCD::ComponentProxy->new('first', $cfg));

my $cl = NCD::ComponentProxyList->new($cfg, undef, qw(first second third));

my @sorted = $cl->_sortComponents(\@unsorted);
is($unsorted[0]->name(), 'second', "Sorting is not in place");

ok(@sorted, "Components are successfully sorted");

# _sortComponents actually returns the list in the reverse order
is($sorted[0]->[0]->name(), "first", "Correct first element in the list");
is($sorted[0]->[1]->name(), "second", "Correct second element in the list");
is($sorted[0]->[2]->name(), "third", "Correct third element in the list");


is($cl->_sortComponents([$unsorted[0]]), undef,
   "Sorting with missing dependencies fails without --nodeps");



$this_app->{CONFIG}->set("nodeps", 1);

ok($cl->_sortComponents([$unsorted[0]]),
   "Sorting with missing dependencies succeeds with --nodeps");

done_testing();
