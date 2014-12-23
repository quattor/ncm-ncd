# -*- mode: cperl -*-
use strict;
use warnings;
use Test::More;
use NCD::ComponentProxyList;
use CAF::Object;
use Test::Quattor qw(get-components-simple);

$CAF::Object::NoAction = 1;

=pod

=head1 DESCRIPTION

Tests for the C<NCD::ComponentProxyList> constructor.  Indirectly we
test the C<_getComponents> method.

=head1 TESTS

=head2 Successful executions

=cut


our $this_app = CAF::Application->new('app');
$this_app->{CONFIG}->define("nodeps");
$this_app->{CONFIG}->set('nodeps', 0);
$this_app->{CONFIG}->define('autodeps');
$this_app->{CONFIG}->set('autodeps', 0);

my $cfg = get_config_for_profile('get-components-simple');

my $cl = NCD::ComponentProxyList->new($cfg, undef, "acomponent");

is(scalar(@{$cl->{CLIST}}), 1, "A component was loaded");

$cl = NCD::ComponentProxyList->new($cfg, undef, qw(acomponent adep));
is(scalar(@{$cl->{CLIST}}), 2, "A component and its dependency were loaded");

$cl = NCD::ComponentProxyList->new($cfg, undef, qw(adep));
is(scalar(@{$cl->{CLIST}}), 1,
   "Dependencies are not loaded with autodeps == 0");

$this_app->{CONFIG}->set('autodeps', 1);
$cl = NCD::ComponentProxyList->new($cfg, undef, qw(adep));
is(scalar(@{$cl->{CLIST}}), 2,
   "Dependencies are loaded even if not directly requested");

my %all_comps = $cl->get_all_components();
is_deeply(\%all_comps,{
    acomponent => 1,
    adep => 1,
    aninactive => 0,
    aninvalid => undef,
}, "All components and their active state");
    
my %comps = $cl->get_component_list();    
is_deeply(\%comps,{
    acomponent => 1,
    adep => 1,
}, "All active components");

$cl = NCD::ComponentProxyList->new($cfg, undef, qw(doesnotexist));
is($cl->{CLIST}, undef, "Failure on non-existing component");

$cl = NCD::ComponentProxyList->new($cfg, undef, qw(aninactive));
is($cl->{CLIST}, undef, "Failure on inactive component");


done_testing();
