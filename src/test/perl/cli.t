use strict;
use warnings;

use Test::More;
use Test::Quattor;
use Test::Quattor::ProfileCache qw(prepare_profile_cache);
use NCD::CLI;
use Test::MockModule;
use LC::Exception;
use CAF::Reporter qw($VERBOSE_LOGFILE);

my $mock_cli = Test::MockModule->new('NCD::CLI');
my $mock_cpl = Test::MockModule->new('NCD::ComponentProxyList');

$mock_cli->mock('_exit', sub { die("exit $_[1]");});

my $ec = LC::Exception::Context->new->will_store_errors;

my $ppc_cfg = prepare_profile_cache('cli');

my $apppath = "target/sbin/ncm-ncd";
my @baseopts = (
    $apppath,
    '--cache_root', $ppc_cfg->{cache_path},
    '--logdir', 'target',
    );

# GetPermissions is unittested in CCM fetch_profilecache_make_cacheroot.t
my $getperms;
*NCD::CLI::GetPermissions = sub {
    shift;
    $getperms = \@_;
    # dopts, fopts, mask; only dopts is relevant
    return ({mode => 0755, group => 20}, {abc => 1}, 1);
};

# main::this_app is used in Component, ComponentProxy and ComponentProxyList
# = uundef is needed to reset the this_app from Test::Quattor
our $this_app = undef;

$mock_cli->mock('_get_uid', 123);
eval { $this_app = NCD::CLI->new(@baseopts); };
ok(!defined($this_app), "no NCD::CLI instance for non-root user");
like($@, qr{^exit -1 at}, "exit called on wrong user failure with code");

$getperms = undef;
reset_caf_path();
$mock_cli->mock('_get_uid', 0);
$this_app = NCD::CLI->new(@baseopts,
                          '--log_group_readable', 'mygroup',
                          '--log_world_readable', 0);
isa_ok($this_app, 'NCD::CLI', 'NCD::CLI created (for root user)');
is_deeply($getperms, [qw(mygroup 0)], "GetPermissions called with log_group/world_readable options");
is_deeply($Test::Quattor::caf_path->{directory},
          [[['target'],{group => 20, mode => 493}]],
          "CAF::Path directory called on logdir");
# ugly, but no other way
is($this_app->_rep_setup()->{$VERBOSE_LOGFILE}, 1, "verbose_logfile is enabled");

my @allopts = map {$_->{NAME}} @{$this_app->app_options()};
is(scalar @allopts, 34, "expected number of options");

my $reportcomps;
$mock_cpl->mock('reportComponents', sub {my $self = shift; $reportcomps = [map {$_->name()} @{$self->{CLIST}}];});

$@ = undef;
$getperms = undef;
reset_caf_path();
$this_app = NCD::CLI->new(@baseopts, '--list');
isa_ok($this_app, 'NCD::CLI', 'NCD::CLI created (for root user)');
# Change previous test when changing the default (so the opposite is tested)
is_deeply($getperms, [undef, 1], "GetPermissions called with default log_group/world_readable options (undef/0)");
eval {$this_app->main($ec);};
like($@, qr{^exit 0 at}, "exit called on --list with code 0");
is_deeply($reportcomps, [qw(bar foo)], "reportComponents called with --list acts on correct list");

is(NCD::CLI::mk_msg({a => 1, b => 2, c => 3, d => 4}),
   "a (1) b (2) c (3) d (4)",
   "mk_msg makes message with sorted components");

is(NCD::CLI::mk_msg({a => 1, b => 2, c => 3, d => 4}, [qw(c a)]),
   "c (3) a (1) b (2) d (4)",
   "mk_msg makes message with presorted clist");

# CLI redirects all perl warnings to the verbose logger
# This is done via global ENV
my $verb;
$mock_cli->mock('verbose', sub {
    my $self = shift;
    $verb = join(" ", @_);
});
$verb = undef;
warn("Test NCD::CLI warning");
like($verb, qr{Perl warning: Test NCD::CLI warning at src/test/perl/cli.t},
   "perl warning logged verbose");
$mock_cli->unmock('verbose');


done_testing();
