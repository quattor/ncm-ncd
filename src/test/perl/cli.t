use strict;
use warnings;

use Test::More;
use Test::Quattor;
use Test::Quattor::ProfileCache qw(prepare_profile_cache);
use NCD::CLI;
use NCD::ComponentProxyList qw(get_states set_state);
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
    '--cfgfile', 'src/test/resources/ncm-ncd.conf.test',
    );

# GetPermissions is unittested in CCM fetch_profilecache_make_cacheroot.t
my $getperms;
{
    no warnings 'redefine';
    *NCD::CLI::GetPermissions = sub {
        shift;
        $getperms = \@_;
        # dopts, fopts, mask; only dopts is relevant
        return ({mode => 0755, group => 20}, {abc => 1}, 1);
    };
}

# main::this_app is used in Component, ComponentProxy and ComponentProxyList
# = uundef is needed to reset the this_app from Test::Quattor
our $this_app = undef;

$mock_cli->mock('_get_uid', 123);
eval { $this_app = NCD::CLI->new(@baseopts); };
ok(!defined($this_app), "no NCD::CLI instance for non-root user");
like($@, qr{^exit -1 at}, "exit called on wrong user failure with code");

$getperms = undef;
reset_caf_path();
CAF::Reporter::init_reporter();
$mock_cli->mock('_get_uid', 0);
$this_app = NCD::CLI->new(@baseopts,
                          '--log_group_readable', 'mygroup',
                          '--log_world_readable', 1,
                          '--verbose_logfile', 0);
isa_ok($this_app, 'NCD::CLI', 'NCD::CLI created (for root user)');
is_deeply($getperms, [qw(mygroup 1)], "GetPermissions called with log_group/world_readable options");
is_deeply($Test::Quattor::caf_path->{directory},
          [[['target'],{group => 20, mode => 493}]],
          "CAF::Path directory called on logdir");
# ugly, but no other way
is($this_app->_rep_setup()->{$VERBOSE_LOGFILE}, 0, "verbose_logfile is disabled");

my @allopts = map {$_->{NAME}} @{$this_app->app_options()};
is(scalar @allopts, 37, "expected number of options");

my $reportcomps;
$mock_cpl->mock('reportComponents', sub {my $self = shift; $reportcomps = [map {$_->name()} @{$self->{CLIST}}];});

$@ = undef;
$getperms = undef;
reset_caf_path();
CAF::Reporter::init_reporter();
$this_app = NCD::CLI->new(@baseopts, '--list');
isa_ok($this_app, 'NCD::CLI', 'NCD::CLI created (for root user)');
# Change previous test when changing the default (so the opposite is tested)
is_deeply($getperms, [undef, 0], "GetPermissions called with default log_group/world_readable options (undef/0)");
is($this_app->_rep_setup()->{$VERBOSE_LOGFILE}, 1, "verbose_logfile is enabled by default");

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

# Test report / report-format
# Also test ComponentProxyList get_states here
$this_app = NCD::CLI->new(@baseopts, '--debug', 5, '--report');
isa_ok($this_app, 'NCD::CLI', 'NCD::CLI created (for root user) 1');
is($this_app->option('report-format'), 'simple', "simple is default report format");

my $this_appn = NCD::CLI->new(@baseopts, '--debug', 5, '--report', '--report-format', 'nagios');
isa_ok($this_appn, 'NCD::CLI', 'NCD::CLI created (for root user) 2');
is($this_appn->option('report-format'), 'nagios', "nagios report format");

my $statedir = $this_app->option('state');
is($statedir, "/var/run/quattor-components", "expected default statedir value (from config file)");

my @pri;
my $mock_print = sub {
    my $self = shift;
    push(@pri, \@_);
};
$mock_cli->mock('_print', $mock_print);

# missing statedir
@pri = qw();
ok(!$this_app->directory_exists($statedir), "statedir $statedir does not exist 1");
is_deeply(get_states($this_app, $statedir), {}, "get_states on missing dir returns empty hashref");

eval {$this_app->main($ec);};
like($@, qr{^exit 0 at}, "report exited with success 1");
ok(!$this_app->directory_exists($statedir), "statedir $statedir does not exist 2");
is($pri[-1]->[0], 'No components with error', "No state directory gives reported componets are all ok");

# empty statedir
ok($this_app->directory($statedir), "statedir created");
ok($this_app->directory_exists($statedir), "statedir $statedir does exist 1");
is_deeply(get_states($this_app, $statedir), {}, "get_states on empty dir returns empty hashref");

@pri = qw();
eval {$this_app->main($ec);};
like($@, qr{^exit 0 at}, "report exited with success 2");
ok($this_app->directory_exists($statedir), "statedir $statedir does exist 2");
is($pri[-1]->[0], 'No components with error', "Empty state directory gives reported componets are all ok");

@pri = qw();
eval {$this_appn->main($ec);};
like($@, qr{^exit 0 at}, "report exited with success 2");
is($pri[-1]->[0], 'OK 0 components with error | failed=0', "Empty state directory gives reported componets are all ok");

# 2 failed comps
$mock_cpl->mock('_mtime', sub {return $_[0] =~ m/woohaa/ ? 123456789 : 987654321});
set_state($this_app, 'woohaa', 'woopsie', $statedir);
set_state($this_app, 'ouch', '', $statedir);
is_deeply(get_states($this_app, $statedir), {
    woohaa => {
        message => "woopsie\n",
        timestamp => 123456789,
    },
    ouch => {
        message => "\n",
        timestamp => 987654321,
    }
}, "get_states on 2 failed components returns hashref");

@pri = qw();
eval {$this_app->main($ec);};
like($@, qr{^exit -1 at}, "report exited with failure");
ok($this_app->directory_exists($statedir), "statedir $statedir does exist 3");
diag explain \@pri;
is($pri[-3]->[0], '2 components with error', "Main report is 2 failed components");
like($pri[-2]->[0], qr{^  ouch failed on .*? 2001 \(no message\)}, "failed ouch component");
like($pri[-1]->[0], qr{^  woohaa failed on .*? 1973 with message woopsie}, "failed woohaa component");

@pri = qw();
eval {$this_appn->main($ec);};
like($@, qr{^exit 2 at}, "nagios report exited with failure 1");
is($pri[-1]->[0], "ERROR 2 components with error: ouch,woohaa | failed=2", "nagios format failed components");

# test nagios format message shortening
foreach my $i (1..50) {
    set_state($this_app, "compo$i", '', $statedir);
}
@pri = qw();
eval {$this_appn->main($ec);};
like($@, qr{^exit 2 at}, "nagios report exited with failure 2");
my $fcomps = join(",", (sort map {"compo$_"} (1..3,10..33)));
is($pri[-1]->[0], "ERROR 52 components with error: $fcomps... | failed=52", "nagios format failed components (shortening)");


#diag explain \@pri;

done_testing();
