# -*- mode: cperl -*-
use strict;
use warnings;
use Test::More;
use Test::Quattor qw(runall-comps);
use NCD::ComponentProxyList;
use NCD::ComponentProxy;
use CAF::Application;
use CAF::Object;

$CAF::Object::NoAction = 1;

=pod

=head1 DESCRIPTION

Tests for the C<NCD::ComponentProxyList::skip_components> method.

=cut

our $this_app = CAF::Application->new('app');
$this_app->{CONFIG}->define("nodeps");
$this_app->{CONFIG}->set('nodeps', 0);

my $err = {};
my $cfg = get_config_for_profile('runall-comps');

my @cmp =(
    NCD::ComponentProxy->new('acomponent', $cfg), 
    NCD::ComponentProxy->new('anotherone', $cfg)
);

my $cl = NCD::ComponentProxyList->new($cfg, undef, qw(acomponent anotherone));

my $comps = {
    acomponent => 1,
    anotherone => 1,
    foo        => 1
};

$cl->{SKIP} = NCD::ComponentProxyList::_parse_skip_args("acomponent,anotherone,doesnotexist");

my %skipped = $cl->skip_components($comps);

is_deeply($comps, {foo => 1}, "All components but foo are skipped");

is_deeply(\%skipped, {
        acomponent => 1,
        anotherone => 1,
        doesnotexist => 0,
}, "Skipped components");

done_testing();
