# -*- mode: cperl -*-
use strict;
use warnings;

BEGIN {
    # Ignore the ncm namespace loaded by Test::Quattor
    use Test::Quattor::Namespace;
    $Test::Quattor::Namespace::ignore->{ncm} = 1;
}

use Test::More;
use Test::Quattor qw(component-proxy-init);
use NCD::ComponentProxy;
use CAF::Object;
use Readonly;
use JSON::XS;
use LC::Exception;

$CAF::Object::NoAction = 1;

# We'll be testing that some instantiations fail (non-existing
# component paths or inactive components).  We just ignore these LC
# exceptions.
our $EC = LC::Exception::Context->new();

sub ignore
{
    my ($e, $ec) = @_;
    $ec->has_been_reported(1);
}

$EC->error_handler(\&ignore);
$EC->warning_handler(\&ignore);


=pod

=head1 DESCRIPTION

Tests for the C<NCD::ComponentProxy::_initialize> method

=head1 TESTS

=head2 The component exists

=over

=item * The component is active

Succeed

=cut

my $cfg = get_config_for_profile("component-proxy-init");

my $cmp = NCD::ComponentProxy->new("foo", $cfg);
isa_ok($cmp, "NCD::ComponentProxy", "Active component foo is loaded");

is($cmp->{NAME}, "foo", "Correct name assigned");
is($cmp->{CONFIG}, $cfg, "Configuration stored in the proxy");
is($cmp->{MODULE}, $cmp->{NAME}, "Name is used as module if no module is listed");

=pod

=item * The component is not active

No proxy is returned

=cut

$cmp = NCD::ComponentProxy->new("bar", $cfg);
is($cmp, undef, "Inactive component bar is not loaded");

=pod

=item * The component exists and is delegated to another module

A proxy is returned and the name is not the

=cut

$cmp = NCD::ComponentProxy->new("baz", $cfg);
isa_ok($cmp, "NCD::ComponentProxy", "Delegated component is instanciated");
is($cmp->{NAME}, "baz", "Correct name assigned");
is($cmp->{MODULE}, "woof", "Correct module assigned");

=pod

=head2 The component doesn't exist

No proxy is returned

=cut

$cmp = NCD::ComponentProxy->new("lkjhljhljh", $cfg);
is($cmp, undef, "Non-existing component receives no proxy");

done_testing();
