use strict;
use warnings;

BEGIN {
    # Ignore the ncm namespace loaded by Test::Quattor
    use Test::Quattor::Namespace;
    $Test::Quattor::Namespace::ignore->{ncm} = 1;
}

use Test::More;
use Test::Quattor qw(component1);
use NCM::Component;
use Test::Quattor::Object;


my $obj = Test::Quattor::Object->new();

my $cmp1 = NCM::Component->new('component1', $obj);
isa_ok($cmp1, 'NCM::Component', 'NCM::Component instance created');
is($cmp1->prefix(), "/software/components/component1", "prefix for component1");

my $cfg1 = get_config_for_profile('component1');
ok(! defined($cmp1->{ACTIVE_CONFIG}), "no ACTIVE_CONFIG attribute set for component1 after init");
my $ret = $cmp1->set_active_config($cfg1);
is($ret, $cmp1->{ACTIVE_CONFIG}, "set_active_config sets and return ACTIVE_CONFIG attribute");
is($ret, $cfg1, "set_active_config set active config to passed value");


done_testing;
