use strict;
use warnings;

BEGIN {
    # Ignore the ncm namespace loaded by Test::Quattor
    use Test::Quattor::Namespace;
    $Test::Quattor::Namespace::ignore->{ncm} = 1;
}

use Test::More;
use Test::Quattor qw(component-execute);
use Test::MockModule;
use Cwd;

my $logdir;
my %ORIG_ENV;

BEGIN {
    # Pick it up here, after Test::Quattor is loaded
    %ORIG_ENV = %ENV;

    $logdir = getcwd()."/target";
    use CAF::Application;
    our $this_app = CAF::Application->new('app');
    $this_app->{CONFIG}->define("noaction");
    $this_app->{CONFIG}->set('noaction', 0);
    $this_app->{CONFIG}->define("multilog");
    $this_app->{CONFIG}->set('multilog', 1);
    $this_app->{CONFIG}->define("logdir");
    $this_app->{CONFIG}->set('logdir', $logdir);
    $this_app->{CONFIG}->define("history");
    $this_app->{CONFIG}->set('history', 1);
}

# Sanity check of the environment we run the tests in
# The idea is that loading the foo component sets this variable
ok(! exists($ENV{TEST_COMPONENTPROXY}), 'ENV variable set by component foo does not exist');

my $mock = Test::MockModule->new('NCD::ComponentProxy');


my $error = 0;
my $lasterror;
$mock->mock('error', sub (@) {
    my $self = shift;
    $lasterror = join(" ", @_);
    diag("ERROR: $lasterror");
    $error++;
});

my $cfg = get_config_for_profile("component-execute");

my $cmp = NCD::ComponentProxy->new("foo", $cfg);
isa_ok($cmp, "NCD::ComponentProxy", "Active component foo is loaded");

is_deeply(\%ENV, \%ORIG_ENV, "initialisation of the Proxy does not modify environment");

# It is in INC via prove commandline
my $incpath = getcwd()."/src/test/perl";
# Change COMPONENT_BASE to this path for further testing
$cmp->{COMPONENT_BASE} = "$incpath/NCM/Component";;

# _load fails

$lasterror = undef;
$mock->mock('_load', sub { return undef;});
ok(! defined($cmp->_execute('Configure')), "_execute fails with undef on failed _load");
is($lasterror, "cannot load component: foo", "_execute reports error on failed _load");

# restore working _load
my $component;
$mock->mock('_load', sub {
    my $load = $mock->original('_load');
    $component = &$load(@_);
    return $component;
});
is($cmp->_load(), $component, "_load returns component");
isa_ok($component, 'NCM::Component::foo',
       '_load returns NCM::Component::foo instance');
ok(! defined($component->{ACTIVE_CONFIG}), "no ACTIVE_CONFIG after load");

is($ENV{TEST_COMPONENTPROXY}, 'a test', 'ENV variable set by component foo correct after load');
delete $ENV{TEST_COMPONENTPROXY};

# _version_check fails
$error = 0;
$mock->mock('_version_check', sub { return undef;});
ok(! defined($cmp->_execute('Configure')), "_execute fails with undef on failed _version_check");
is($error, 0, "_execute reports no error on failed _version_check (assumes this is done by _version_check itself)");

is_deeply(\%ENV, \%ORIG_ENV, "failures in _execute do not modify environment");

# _version_check always ok from now on
$mock->mock('_version_check', 1);

# multilog
my $initlog;
$mock->mock('init_logfile', sub {shift; $initlog = join(" ", @_); return 1;});
# history
my $history;
$mock->mock('set_report_history', sub {shift; $history = 1; return 1;});

$component = undef;

is_deeply($cmp->_execute('Configure'),
          { WARNINGS => 2, ERRORS => 3 },
          "succesful Configure of component foo returns errors/warnings hashref");

is($initlog, "$logdir/component-foo.log at", "component foo logfile initialised with multilog");
ok($history, "history reporting enabled");
isa_ok($component, 'NCM::Component::foo', '_load from Configure NCM::Component::foo instance');

is_deeply(\%ENV, \%ORIG_ENV, "_execute does not modify environment");

is($component->{_config}, $cfg, "configuration instance passed during ComponentProxy init is passed to component foo Configure");
is($component->{ACTIVE_CONFIG}, $cfg, "configuration instance set as ACTIVE_CONFIG by ComponentProxy");
is($component->{_active_config}, $cfg, "configuration instance set as ACTIVE_CONFIG before Configure was called");

# TODO: test noaction
# TODO: test errors/warnings
# TODO: test all sorts of failures with die()

done_testing();
