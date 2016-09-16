use strict;
use warnings;

BEGIN {
    # Ignore the ncm namespace loaded by Test::Quattor
    use Test::Quattor::Namespace;
    $Test::Quattor::Namespace::ignore->{ncm} = 1;
}

use Test::More;

use Test::Quattor qw(component1 component-fqdn);
use Test::Quattor::Object;

# insert the this_app before load but after Test::Quattor
BEGIN {
    use CAF::Application;
    our $this_app = CAF::Application->new('app');
    $this_app->{CONFIG}->define("noaction");
    $this_app->{CONFIG}->set('noaction', 123);
}

use NCM::Component;


=head1 NoAction is set on load via this_app

=cut

is($NCM::Component::NoAction, 123, "NoAction set via this_app onload");

my $obj = Test::Quattor::Object->new();

=head1 test NCM::Component init

=cut

my $cmp1 = NCM::Component->new('component1', $obj);
isa_ok($cmp1, 'NCM::Component', 'NCM::Component instance 1 created');
is($cmp1->prefix(), "/software/components/component1", "prefix for component1");

=head1 test set_active_config

=cut

my $cfg1 = get_config_for_profile('component1');
ok(! defined($cmp1->{ACTIVE_CONFIG}), "no ACTIVE_CONFIG attribute set for component1 after init");
my $ret = $cmp1->set_active_config($cfg1);
is($ret, $cmp1->{ACTIVE_CONFIG}, "set_active_config sets and return ACTIVE_CONFIG attribute");
is($ret, $cfg1, "set_active_config set active config to passed value");

=head1 test NCM::Component init with active config

=cut

my $cmp2 = NCM::Component->new('component2', $obj, config => $cfg1);
isa_ok($cmp2, 'NCM::Component', 'NCM::Component instance 2 created');
is($cmp2->{ACTIVE_CONFIG}, $cfg1, "active config attribute set via init");

done_testing;
