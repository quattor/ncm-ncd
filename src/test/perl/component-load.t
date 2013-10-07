# -*- mode: cperl -*-
use strict;
use warnings;
use Test::More;
use Test::Quattor qw(component-load);
use NCD::ComponentProxy;
use CAF::Object;
use Readonly;
use JSON::XS;
use LC::Exception;
use Test::MockModule;

my $mock = Test::MockModule->new("NCD::ComponentProxy");
$mock->mock("hasFile", 1);

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

Tests for the C<NCD::ComponentProxy::_load> method

=head1 TESTS

=head2 The component can be loaded

=over

=item * A component with no overriden module will be loaded

The name of the component is used as the Perl module to load

=cut

my $cfg = get_config_for_profile("component-load");

my $cmp = NCD::ComponentProxy->new("foo", $cfg);
isa_ok($cmp, "NCD::ComponentProxy", "Active component foo is loaded");

my $c;

eval {$c = $cmp->_load();};
ok(!$@, "No exceptions were raised when loading foo");
isa_ok($c, "NCM::Component::foo", "Component foo correctly instantiated");

=pod

=item * The ncm-module field overrides the module name

=cut

$cmp = NCD::ComponentProxy->new("bar", $cfg);
isa_ok($cmp, "NCD::ComponentProxy", "Component bar is loaded");

eval {$c = $cmp->_load() };
ok(!$@, "No exceptions raised when loading foo");
isa_ok($c, "NCM::Component::foo", "Component path bar will actually run foo");

=pod

=head2 The module cannot be loaded

=cut

$cmp->{MODULE} = "klhljhljh";
$c = $cmp->_load();
is($c, undef, "Non-existing module is not loaded");

done_testing();
