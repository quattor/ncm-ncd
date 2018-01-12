use strict;
use warnings;

BEGIN {
    # Ignore the ncm namespace loaded by Test::Quattor
    use Test::Quattor::Namespace;
    $Test::Quattor::Namespace::ignore->{ncm} = 1;
}

use Test::More;
use Test::Quattor qw(component1 component-fqdn component1_redirect component1_redirect_none);
use Test::Quattor::Object;

# insert the this_app before load but after Test::Quattor
BEGIN {
    use CAF::Application;
    our $this_app = CAF::Application->new('app');
    $this_app->{CONFIG}->define("noaction");
    $this_app->{CONFIG}->set('noaction', 123);
}

use NCM::Component;
use NCM::Component::component1;

=head1 NoAction is set on load via this_app

=cut

is($NCM::Component::NoAction, 123, "NoAction set via this_app onload");

my $obj = Test::Quattor::Object->new();

=head1 test NCM::Component init

=cut
my $cfg = get_config_for_profile('component1');
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

=head1 Configure / Unconfigure

=cut

ok(!defined($cmp1->Configure($cfg)), "NCM::Component returns undef (not implemented)");
is($obj->{LOGLATEST}->{ERROR}, 'Configure() method not implemented by component', 'Configure not implemented error');

ok(!defined($cmp1->Unconfigure($cfg)), "NCM::Component returns undef (not implemented)");
is($obj->{LOGLATEST}->{ERROR}, 'Unconfigure() method not implemented by component', 'Unconfigure not implemented error');

=head1 redirect

=cut

my $cfgr = get_config_for_profile('component1_redirect');

$cmp1 = NCM::Component::component1->new('component1', $obj);
isa_ok($cmp1, 'NCM::Component::component1', 'is a NCM::Component::component1');
is($cmp1->Configure($cfg), 'NCM::Component::Component1::Regular Configure', 'Redirect to default Regular');
isa_ok($cmp1, 'NCM::Component::Component1::Regular', 'is now a NCM::Component::Component1::Regular');
ok(!defined($cmp1->Unconfigure($cfg)), 'Redirect to default Regular has no Unconfigure');


$cmp1 = NCM::Component::component1->new('component1', $obj);
isa_ok($cmp1, 'NCM::Component::component1', 'is a NCM::Component::component1');
ok(!defined($cmp1->Configure($cfgr)), 'Redirect to name Subby has no Configure');
isa_ok($cmp1, 'NCM::Component::Component1::Subby', 'is now a NCM::Component::Component1::Subby');
is($cmp1->Unconfigure($cfgr), 'NCM::Component::Component1::Subby Unconfigure', 'Redirect to name Subby');

my $cfgn = get_config_for_profile('component1_redirect_none');
$cmp1 = NCM::Component::component1->new('component1', $obj);
ok(!defined($cmp1->Configure($cfgn)), "NCM::Component returns undef (redirect does not exist)");
like($obj->{LOGLATEST}->{ERROR},
     qr{REDIRECT bad Perl code in NCM::Component::Component1::DoesNotExist: Can't locate NCM/Component/Component1/DoesNotExist.pm in \@INC},
     'redirect does not exist error');


done_testing;
