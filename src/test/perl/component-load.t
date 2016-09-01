use strict;
use warnings;

BEGIN {
    # Ignore the ncm namespace loaded by Test::Quattor
    use Test::Quattor::Namespace;
    $Test::Quattor::Namespace::ignore->{ncm} = 1;
}

use Test::More;
use Test::Quattor qw(component-load);
use NCD::ComponentProxy;
use CAF::Object;
use Readonly;
use JSON::XS;
use LC::Exception;
use Test::MockModule;
use Cwd;
use version;

use Readonly;
Readonly my $COMPONENT_BASE => "/usr/lib/perl/NCM/Component";

$CAF::Object::NoAction = 1;

BEGIN {
    use CAF::Application;
    our $this_app = CAF::Application->new('app');
    $this_app->{CONFIG}->define("noaction");
    $this_app->{CONFIG}->set('noaction', 1);
    $this_app->{CONFIG}->define("template-path");
    $this_app->{CONFIG}->set('template-path', "doesnotexist");
}

my $error = 0;
my $lasterror;
my $mock = Test::MockModule->new('NCD::ComponentProxy');
$mock->mock('error', sub (@) {
    my $self = shift;
    $lasterror = join(" ", @_);
    diag("ERROR: $lasterror");
    $error++;
});

diag explain \@INC;

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

# It is in INC via prove commandline
my $incpath = getcwd()."/src/test/perl";
# Change COMPONENT_BASE to this path for further testing
my $modpath = "$incpath/NCM/Component";

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

is($cmp->{COMPONENT_BASE},
   $COMPONENT_BASE,
   "Default module base path as expected");
is($cmp->getComponentFilename(), "$COMPONENT_BASE/foo.pm",
   "getComponentFilename returned expected module filename");

$cmp->{COMPONENT_BASE} = $modpath;
is($cmp->getComponentFilename(), "$modpath/foo.pm",
   "getComponentFilename returned expected module filename for foo");
ok($cmp->hasFile(), "Found NCM::Component::foo");

my $c;

eval {$c = $cmp->_load();};
ok(!$@, "No exceptions were raised when loading foo");
isa_ok($c, "NCM::Component::foo", "Component foo correctly instantiated");
is($cmp->{VERSION_PACKAGE}, version->new('1.2.3'), "Version from package set");

=pod

=item * The ncm-module field overrides the module name

=cut

$cmp = NCD::ComponentProxy->new("bar", $cfg);
isa_ok($cmp, "NCD::ComponentProxy", "Component bar is loaded");
$cmp->{COMPONENT_BASE} = $modpath;

eval {$c = $cmp->_load() };
ok(!$@, "No exceptions raised when loading foo");
isa_ok($c, "NCM::Component::foo", "Component path bar will actually run foo");
is($c->prefix(), "/software/components/bar",
   "Prefix is preserved when ncm-module is specified");
is($cmp->{VERSION_PACKAGE}, version->new('1.2.3'), "Version from package set (bar use foo module)");

=pod

=item * The ncm-module field is namespaced

=cut

$cmp = NCD::ComponentProxy->new("baz", $cfg);
isa_ok($cmp, "NCD::ComponentProxy", "Component baz is loaded");
$cmp->{COMPONENT_BASE} = $modpath;
ok(! defined ($cmp->{VERSION_PACKAGE}), "No VERSION_PACKAGE set with baz");

eval {$c = $cmp->_load()};
ok(!$@, "No exceptions raised when loading spma::ips");
is($c->prefix(), "/software/components/baz",
   "Prefix is preserved with namespaced ncm-module's");

=pod

=head2 The module cannot be loaded

=cut

# module is missing
$cmp->{MODULE} = "doesnotexist";
ok(! -f $cmp->getComponentFilename(), "Module does not exists");
ok(! $cmp->hasFile(), "hasFile fails on non-existing module");

$error = 0;
$c = $cmp->_load();
is($c, undef, "Non-existing module is not loaded");
is($error, 1, "error logged for non-existing module");
like($lasterror, qr{component doesnotexist is not installed},
     "non-existing module error message");

# invalid perl code
$error = 0;
$cmp->{MODULE} = "invalidperl";
ok($cmp->hasFile(), "invalidperl module found");

$c = $cmp->_load();
is($c, undef, "invalidperl module is not loaded");
is($error, 1, "error logged for invalidperl");
like($lasterror, qr{bad Perl code in},
     "invalid perl error message");

# missing EC package variable
$error = 0;
$cmp->{MODULE} = "missingec";
ok($cmp->hasFile(), "missingec module found");

$c = $cmp->_load();
is($c, undef, "module with missing EC is not loaded");
is($error, 1, "error logged for missing EC package variable");
like($lasterror, qr{bad component exception handler},
     "missing EC package variable error message");

# borkennew is missing a new method (i.e. not a subclass of NCM::Component)
$error = 0;
$cmp->{MODULE} = "brokennew";
ok($cmp->hasFile(), "brokennew module found");

$c = $cmp->_load();
is($c, undef, "module with broken/missing new method is not loaded");
is($error, 1, "error logged for brokennew");
like($lasterror, qr{instantiation statement fails},
     "broken new error message");

# noconfigure is missing a Configure method
$error = 0;
$cmp->{MODULE} = "noconfigure";
ok($cmp->hasFile(), "noconfigure module found");

$c = $cmp->_load();
is($c, undef, "module with missing Configure method is not loaded");
is($error, 1, "error logged for missingconfigure");
like($lasterror, qr{missing the mandatory Configure method},
     "missing configure error message");

=pod

=head2 Load component that does not inherit from C<NCM::Component>

=cut

$error = 0;
$cmp->{MODULE} = "customcomponent";
ok($cmp->hasFile(), "customcomponent module found");

$c = $cmp->_load();
isa_ok($c, "NCM::Component::customcomponent",
       "customcomponent correctly instantiated");
is($error, 0, "no error logged for customcomponent");


done_testing();
