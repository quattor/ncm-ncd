use strict;
use warnings;

use Test::More;
use Test::Quattor::ProfileCache qw(prepare_profile_cache);
use NCD::CLI;
use Test::MockModule;
use LC::Exception;
use CAF::Reporter qw($VERBOSE_LOGFILE);

my $mock_cli = Test::MockModule->new('NCD::CLI');
my $mock_cpl = Test::MockModule->new('NCD::ComponentProxyList');

$mock_cli->mock('_exit', sub { shift; my $exitcode = shift; die("exit $exitcode");});

my $ec = LC::Exception::Context->new->will_store_errors;

my $ppc_cfg = prepare_profile_cache('cli');

my $apppath = "target/sbin/ncm-ncd";
my @baseopts = (
    $apppath,
    '--cache_root', $ppc_cfg->{cache_path},
    '--logdir', 'target',
    );

# main::this_app is used in Component, ComponentProxy and ComponentProxyList
our $this_app;

$mock_cli->mock('_get_uid', 123);
eval { $this_app = NCD::CLI->new(@baseopts); };
ok(!defined($this_app), "no NCD::CLI instance for non-root user");
like($@, qr{^exit -1 at}, "exit called on wrong user failure with code");

$mock_cli->mock('_get_uid', 0);
$this_app = NCD::CLI->new(@baseopts);
isa_ok($this_app, 'NCD::CLI', 'NCD::CLI created (for root user)');
# ugly, but no other way
is($this_app->_rep_setup()->{$VERBOSE_LOGFILE}, 1, "verbose_logfile is enabled");

my @allopts = map {$_->{NAME}} @{$this_app->app_options()};
is(scalar @allopts, 32, "expected number of options");

my $reportcomps;
$mock_cpl->mock('reportComponents', sub {my $self = shift; $reportcomps = [map {$_->name()} @{$self->{CLIST}}];});

$@ = undef;
$this_app = NCD::CLI->new(@baseopts, '--list');
isa_ok($this_app, 'NCD::CLI', 'NCD::CLI created (for root user)');
eval {$this_app->main($ec);};
like($@, qr{^exit 0 at}, "exit called on --list with code 0");
is_deeply($reportcomps, [qw(bar foo)], "reportComponents called with --list acts on correct list");

is(NCD::CLI::mk_msg({a => 1, b => 2, c => 3, d => 4}),
   "a (1) b (2) c (3) d (4)",
   "mk_msg makes message with sorted components");

is(NCD::CLI::mk_msg({a => 1, b => 2, c => 3, d => 4}, [qw(c a)]),
   "c (3) a (1) b (2) d (4)",
   "mk_msg makes message with presorted clist");

done_testing();
