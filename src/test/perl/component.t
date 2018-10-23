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

=head1 get_tree method

=cut

ok(! defined($cmp2->{fail}), "fail attribute is not set");

$cmp2->{ACTIVE_CONFIG}->{fail} = 'something';
is_deeply($cmp2->get_tree("/system"), {network => {hostname => 'short', domainname => 'example.com'}},
    "get_tree with absolute path returns tree from path");
ok(! defined($cmp2->{ACTIVE_CONFIG}->{fail}), "fail attribute of active config is reset");
ok(! defined($cmp2->{fail}), "fail attribute is not set on success");

is_deeply($cmp2->get_tree(), {active => 1, special => {subtree => 1}},
    "get_tree without path return tree from prefix");
is_deeply($cmp2->get_tree("special"), {subtree => 1},
    "get_tree with relative path return tree relative to prefix");

# Test failure
ok(! defined($cmp2->{fail}), "No fail attr set before testing failing get_tree");

# invalid path is an error
ok(!defined($cmp2->get_tree("//invalid/path")), "invalid path returns undef");
is($cmp2->{fail}, "*** path //invalid/path must be an absolute path: start '', remainder  / invalid / path",
   "fail attribute set with message after failing get_tree with invalid path");

# non-existing path is not an error
# should reset previous failure
ok(!defined($cmp2->get_tree("/non/existing/path")), "non-existing path returns undef");
ok(! defined($cmp2->{fail}), "non-existing path does not set fail attribute with get_tree");


=head2 get_fqdn

=cut

ok(! defined($cmp2->get_tree("/system/network/realhostname")), "realhostname not set");
is($cmp2->get_fqdn(), "short.example.com", "fqdn from hostname and domainname in absence of realhostname");

my $cfg_fqdn = get_config_for_profile('component-fqdn');
$cmp2->set_active_config($cfg_fqdn);
my $realhostname = "something.else.example.org";
is($cmp2->get_tree("/system/network/realhostname"), $realhostname, "realhostname set");
is($cmp2->get_fqdn(), $realhostname, "fqdn from realhostname");


done_testing;
