use strict;
use warnings;

BEGIN {
    # Ignore the ncm namespace loaded by Test::Quattor
    use Test::Quattor::Namespace;
    $Test::Quattor::Namespace::ignore->{ncm} = 1;
}

use Test::More;
use Test::Quattor qw(component-proxy-list);
use NCD::ComponentProxyList qw(get_statefile set_state); # Test the imports
use CAF::Object;
use CAF::Path;
use Test::MockModule;
use Cwd;


$CAF::Object::NoAction = 1;

our $this_app;

BEGIN {
    $this_app = CAF::Application->new('app');
    $this_app->{CONFIG}->define("state");
    $this_app->{CONFIG}->define("autodeps");
    $this_app->{CONFIG}->set('autodeps', 1);
    $this_app->{CONFIG}->define("noaction");
    $this_app->{CONFIG}->set('noaction', 1);
    $this_app->{CONFIG}->define("nodeps");
    $this_app->{CONFIG}->set('nodeps', 0);
    $this_app->{CONFIG}->define("debug");
    $this_app->{CONFIG}->set('debug', 3);
}

my $cfg = get_config_for_profile('component-proxy-list');

my $mock = Test::MockModule->new('NCD::ComponentProxyList');

my $WARN = 0;
$mock->mock('warn', sub (@) {
    my $self= shift;
    $WARN++;
    diag("WARN ", join('', @_));
});

my $ERROR = 0;
$mock->mock('error', sub (@) {
    my $self= shift;
    $ERROR++;
    diag("ERROR ", join('', @_));
});


$mock->mock('debug', sub (@) {
    my $self= shift;
    diag("DEBUG ", join('', @_));
});


$mock->mock('verbose', sub (@) {
    my $self= shift;
    diag("VERBOSE ", join('', @_));
});

my @unlinked;
$mock->mock('_unlink', sub {
    my ($self, $file) = @_;
    push(@unlinked, $file);
});


=head1

Test Init

=cut

# mock a failing _getComponents
$mock->mock('_getComponents', undef);

# no skip; random order
my @comps = qw(ee bb dd);
my $cpl = NCD::ComponentProxyList->new($cfg, undef, \@comps, "/somewhere");
isa_ok($cpl, 'NCD::ComponentProxyList', 'init returns a NCD::ComponentProxyList instance');

is_deeply($cpl->{CCM_CONFIG}, $cfg, "Configuration instance CCM_CONFIG");
is_deeply($cpl->{SKIP}, [], "Empty skip list");
is_deeply($cpl->{NAMES}, \@comps, "Correct list of initial components");
is($cpl->{RUN_FROM}, "/somewhere", "Correct run_from passed as 4th arg");

my $cpl2 = NCD::ComponentProxyList->new($cfg, undef, \@comps);
isa_ok($cpl2, 'NCD::ComponentProxyList', 'init returns a NCD::ComponentProxyList instance 2');
is($cpl2->{RUN_FROM}, "/tmp", "Correct default /tmp run_from");

ok(! defined($cpl->{CLIST}), "Component proxies list is undefined in case of failure of _getComponents");

$mock->unmock('_getComponents');

=head1

Test _parse_skip_args

=cut

my $skip = NCD::ComponentProxyList::_parse_skip_args("a,b,c");
is_deeply($skip, ['a', 'b', 'c'], "Correct list of componets to skip returned");
$skip = NCD::ComponentProxyList::_parse_skip_args();
is_deeply($skip, [], "Empty list of componets to skip returned");

=head1

get_all_components / get_component_list

=cut

my %comps = $cpl->get_all_components();
is_deeply(\%comps, {
    'aa' => 1,
    'bb' => 1,
    'cc' => 1,
    'dd' => 1,
    'ee' => 1,
    'ff' => 0,
    'gg' => 1,
          }, "All components and their active status");

my %actcomps = $cpl->get_component_list();
is_deeply(\%actcomps, {
    'aa' => 1,
    'bb' => 1,
    'cc' => 1,
    'dd' => 1,
    'ee' => 1,
    'gg' => 1,
          }, "All active components and their active status");

=head1

skip_components

=cut

# Take copy
my $comps = { %comps };

$cpl->{SKIP} = ['aa', 'ee', 'xx'];
my %toskip = $cpl->skip_components($comps);
is_deeply($comps, {
    'bb' => 1,
    'cc' => 1,
    'dd' => 1,
    'ff' => 0,
    'gg' => 1,
          }, "Filtered hashref of comps remains");
is_deeply(\%toskip, {
    'aa' => 1,
    'ee' => 1,
    'xx' => 0,
          }, "Status of to be skipped components");

=head1

get_proxies

=cut

# autodeps on, nodeps off
$WARN=0;
$ERROR=0;

$comps = { %comps };

# delete aa, predep of almost everything
delete $comps->{aa};
# delete dd, post dep of bb
delete $comps->{dd};
# delete gg, has no deps on anything
delete $comps->{gg};
# delete ff, since not active; can't make proxy
delete $comps->{ff};

my @pxs = $cpl->get_proxies($comps);
is_deeply($comps, {
    'aa' => 1,
    'bb' => 1,
    'cc' => 1,
    'dd' => 1,
    'ee' => 1,
    # no gg
          }, "Modified comps after recursive dependency search");
my @names = map { $_->name() } @pxs;
is_deeply(\@names, ['bb','cc','ee','aa','dd'],
          "Expected names of components proxies");
is($ERROR, 0, "no errors logged");
is($WARN, 0, "no warn logged");

my $px = $pxs[0];
diag explain $px;
isa_ok($px, 'NCD::ComponentProxy', "get_proxies returns list of ComponentProxy instances");
is($px->{RUN_FROM}, "/somewhere", "proxies initialised with same run_from");

# autodeps off, nodeps off
# no recursive search due to no missing deps from autodeps
# no errors on missing deps due to nodeps

$WARN=0;
$ERROR=0;

$this_app->{CONFIG}->set('autodeps', 0);

$comps = { %comps };

# delete aa, predep of almost everything
delete $comps->{aa};
# delete dd, post dep of bb
delete $comps->{dd};
# delete gg, has no deps on anything
delete $comps->{gg};
# delete ff, since not active; can't make proxy
delete $comps->{ff};

@pxs = $cpl->get_proxies($comps);
is_deeply($comps, {
    'bb' => 1,
    'cc' => 1,
    'ee' => 1,
          }, "Modified comps after search (autodeps off, nodeps off)");

@names = map { $_->name() } @pxs;
is_deeply(\@names, ['bb','cc','ee'],
          "Expected names of components proxies with autodeps off");
is($ERROR, 0, "no errors logged");
is($WARN, 2, "warn logged (aa missing twice)");

# turn autodeps on again
$this_app->{CONFIG}->set('autodeps', 1);

=head1

reportComponents

=cut


my @report;
$mock->mock('report', sub (@) {
    my ($self, @args) = @_;
    my $msg = join('', @args);
    push(@report, $msg);
});

$cpl->{CLIST} = \@pxs;
$cpl->reportComponents();

is_deeply(\@report, [
              'active components found inside profile /software/components:',
              'name           predeps                      postdeps                     ',
              '-------------------------------------------------------------------',
              'bb:            aa                           cc,dd                        ',
              'cc:                                                                      ',
              'ee:            aa                                                        '
          ], "report as expected");

$mock->unmock('report');
$cpl->{CLIST} = undef;

=head1

pre_config_actions / post_config_actions

=cut

# there's nothing in the test framework to access the options passed

$comps = { %comps };

set_desired_output("/test/pre", "preout");
set_command_status("/test/pre", 0);

ok($cpl->pre_config_actions("/test/pre", 10, $comps),
   "Pre hook ran succesful");

set_desired_output("/test/post", "postout");
set_command_status("/test/post", 0);

ok($cpl->post_config_actions("/test/post", 10, $comps),
   "Post hook ran succesful");

ok(command_history_ok(["/test/pre", "/test/post"]),
   "Pre and post hook ran");

=head1

get_statefile / set_state (via _set_state method) / clear_state

Pass cpl instance as logger instance for function

=cut

# reset unlinked
@unlinked = ();

my $cafpath = CAF::Path::mkcafpath();
my $mytestcomp = "mytestcomponent";
my $relpath = 'target/statefiles';
ok(!$cafpath->directory_exists($relpath), "No statesfiles dir exists ($relpath)");
$this_app->{CONFIG}->set('state', $relpath);
ok(! defined(get_statefile($cpl, $mytestcomp, $this_app->option('state'))),
   "get_statefile returns undef in case of failure (relpath instead of abspath)");
ok(!$cafpath->directory_exists($relpath), "states dir not created in case of failure");

my $abspath = getcwd()."/$relpath";
my $absstatefile = "$abspath/$mytestcomp";
ok(!$cafpath->directory_exists($abspath), "No statesfiles dir exists ($abspath)");
$this_app->{CONFIG}->set('state', $abspath);
is(get_statefile($cpl, $mytestcomp, $this_app->option('state')),
   $absstatefile,
   "get_statefile returns expected statefile $absstatefile");
ok($cafpath->directory_exists($abspath), "states dir created in case of success");

# test noaction
$this_app->{CONFIG}->set('noaction', 1);

my $statemessage = "my message";

ok(! defined($cpl->_set_state($mytestcomp, $statemessage)),
   "set_state returns undef with noaction option");

ok(! defined($cpl->clear_state($mytestcomp)),
   "set_state returns undef with noaction option");

ok(! @unlinked, "no files removed with noaction flag set");

# can't make actual file with FileWriter?
$this_app->{CONFIG}->set('noaction', 0);

ok($cpl->_set_state($mytestcomp, $statemessage),
   "set_state returns 1 without noaction option");

my $statefh = get_file($absstatefile);
isa_ok($statefh, 'CAF::FileWriter', "statefile $absstatefile is a CAF::FileWriter");
is("$statefh", "$statemessage\n", "contents of statefile $absstatefile as expected ($statemessage)");

ok($cpl->clear_state($mytestcomp),
   "set_state returns 1 without noaction option");

is_deeply(\@unlinked, [$absstatefile],
    "unlink called once with expected statefile $absstatefile");

# reset noaction
$this_app->{CONFIG}->set('noaction', 1);

=head1

missing_deps

=cut

# 'bb' has pre on 'aa' and post on 'cc' and 'dd'
my $knowncomps = {
    'aa' => 0, # even if inactive, aa is not 'missing'
    'cc' => 1,
};

$WARN=0;
$ERROR=0;

my $bb_px = $pxs[0];
is($bb_px->name(), 'bb', "testing with the bb component proxy instance");

# autodeps=1 / nodeps=0 (nodeps doesn't matter with autodeps on)
$this_app->{CONFIG}->set('autodeps', 1);
$this_app->{CONFIG}->set('nodeps', 0);

my @missingcomps = $cpl->missing_deps($bb_px, $knowncomps);
is_deeply(\@missingcomps, ['dd'], "Found expected missing deps from bb with autodeps=1 / nodeps=0");

# autodeps=0 / nodeps=1 (nodeps causes verbose logging, no warn)
is($WARN, 0, "No warnings with autodeps=1");
is($ERROR, 0, "No errors with autodeps=1");

$this_app->{CONFIG}->set('autodeps', 0);
$this_app->{CONFIG}->set('nodeps', 1);

my $res = $cpl->missing_deps($bb_px, $knowncomps);
ok(defined($res), "missing_deps returns defined for autodeps=0 / nodeps=1");
# just to check for array context
@missingcomps = $cpl->missing_deps($bb_px, $knowncomps);
is_deeply(\@missingcomps, [], "No missing deps from bb with autodeps=0 / nodeps=1");
# no errors/warnings with nodeps=1
is($WARN, 0, "No warnings with autodeps=0 / nodeps=1");
is($ERROR, 0, "No errors with autodeps=0 / nodeps=1");

$this_app->{CONFIG}->set('nodeps', 0);
$res = $cpl->missing_deps($bb_px, $knowncomps);
ok(! defined($res), "missing_deps returns undef for autodeps=0 / nodeps=0");
is($WARN, 1, "One warning for 1 missing dep with autodeps=0 / nodeps=0");
is($ERROR, 0, "No errors with autodeps=0 / nodeps=0");
# just to check for array context
@missingcomps = $cpl->missing_deps($bb_px, $knowncomps);
is_deeply(\@missingcomps, [], "No missing deps from bb with autodeps=0 / nodeps=0");

=head1

Test _getComponents

=cut

$WARN=0;
$ERROR=0;

# autodeps=1 / nodeps=0 (nodeps doesn't matter with autodeps on)
$this_app->{CONFIG}->set('autodeps', 1);
$this_app->{CONFIG}->set('nodeps', 0);

# skip nothing
$cpl->{SKIP} = [];

# empty names, try to get all active components
$cpl->{NAMES} = [];
ok($cpl->_getComponents(), "_getComponents returns success with all components");

my $clist_comps;
$clist_comps->{$_->name()}++ foreach @{$cpl->{CLIST}};
%actcomps = $cpl->get_component_list();
is_deeply($clist_comps, \%actcomps,
          "Component proxy list is same as all active components");

# try with bb and dd (who have sane dependencies on each other)
$cpl->{NAMES} = ['bb', 'dd'];
ok($cpl->_getComponents(), "_getComponents returns success with bb+dd");

$clist_comps = {};
$clist_comps->{$_->name()}++ foreach @{$cpl->{CLIST}};
is_deeply($clist_comps, {
    'bb' => 1,
    'dd' => 1,
    'aa' => 1, # pre dep of bb and dd
    'cc' => 1, # post dep bb
},
          "Component proxy list is as expected for bb+dd.");

# test SKIP

$cpl->{SKIP} = ['aa', 'ee'];
$cpl->{NAMES} = ['bb', 'dd', 'ee'];
ok($cpl->_getComponents(), "_getComponents returns success with bb+dd and aa+ee skipped");
$clist_comps = {};
$clist_comps->{$_->name()}++ foreach @{$cpl->{CLIST}};
# ee is actually filtered, dependency aa not
is_deeply($clist_comps, {
    'aa' => 1, # the skip filter is performed before the recursive dependency  resolution
    'bb' => 1,
    'dd' => 1,
    'cc' => 1, # post dep bb
},
          "Component proxy list is as expected for bb+dd and aa+ee skipped.");


is($WARN, 0, "No warnings with _getComponents");
is($ERROR, 0, "No errors with _getComponents");

# test error for
# missing component
$cpl->{CLIST} = undef;
$cpl->{SKIP} = [];
$cpl->{NAMES} = ['bb', 'dd', 'ee', 'xx'];
ok(! defined($cpl->_getComponents()),
   "_getComponents returns undef with missing component in selection list");
ok(! defined($cpl->{CLIST}), "CLIST attribute is not updated with missing component");
is($WARN, 0, "No warnings with _getComponents");
is($ERROR, 1, "error logged with missing component with _getComponents");
$ERROR=0;

# inatcive component
$cpl->{NAMES} = ['bb', 'dd', 'ee', 'ff'];
ok(! defined($cpl->_getComponents()),
   "_getComponents returns undef with inactive component in selection list");
ok(! defined($cpl->{CLIST}), "CLIST attribute is not updated with inactive component");
is($WARN, 0, "No warnings with _getComponents");
is($ERROR, 1, "error logged with missing component with _getComponents");
$ERROR=0;

# no active components (mock get_component_list)
$cpl->{NAMES} = [];
$mock->mock('get_component_list', sub {return});

ok(! defined($cpl->_getComponents()),
   "_getComponents returns undef with 0 active components configured");
ok(! defined($cpl->{CLIST}), "CLIST attribute is not updated with 0 active components configured");
is($WARN, 0, "No warnings with _getComponents");
is($ERROR, 1, "error logged with 0 active components configured with _getComponents");
$ERROR=0;
$mock->unmock('get_component_list');

# skip so many components, no proxies are left (mock skip_components)
$cpl->{SKIP} = ['aa']; # no skip_components if empty
$mock->mock('skip_components', sub {
    my ($self, $comps) = @_;
    # empty the hashref, don't assign new one
    delete $comps->{$_} foreach keys %$comps;
});
ok(! defined($cpl->_getComponents()),
   "_getComponents returns undef with all active components skipped");
ok(! defined($cpl->{CLIST}), "CLIST attribute is not updated with all active components skipped");
is($WARN, 0, "No warnings with _getComponents");
is($ERROR, 1, "error logged with all active components skipped with _getComponents");
$ERROR=0;
$mock->unmock('skip_components');

=head1

Test _sortComponents

=cut

# TODO: more tests of error conditions
$cpl->{SKIP} = [];
# no pre/post deps
$cpl->{NAMES} = ['aa'];
ok($cpl->_getComponents(), "_getComponents returns success with bb+dd");
my $sorted = $cpl->_sortComponents($cpl->{CLIST});
my @compnames = map {$_->name()} @$sorted;
# the order of dd and cc is not relevant, but should be consistent
is_deeply(\@compnames, ['aa'],
          "Sorted component without deps as expected");



$cpl->{SKIP} = [];
$cpl->{NAMES} = ['bb', 'dd'];
ok($cpl->_getComponents(), "_getComponents returns success with bb+dd");
$sorted = $cpl->_sortComponents($cpl->{CLIST});
@compnames = map {$_->name()} @$sorted;
# the order of dd and cc is not relevant, but should be consistent
is_deeply(\@compnames, ['aa', 'bb', 'dd', 'cc'],
          "Sorted components as expected");



=head1

Test _topoSort

=cut

# TODO more tests of error conditions

my $topoafter = {
    'a' => { 'b' => 1},
    'b' => { 'c' => 1},
    'c' => { 'd' => 1},
};
my $topovisited = {};
my $toposorted  = [()];
foreach my $c (sort keys(%$topoafter)) {
    # this is based on the sort init from _sortComponents
    ok($cpl->_topoSort($c, $topoafter, $topovisited, {}, $toposorted, 1),
       "No error on sort (iteration $c)");
}
is_deeply($toposorted, [qw(a b c d)], "correct sorted topo after");


# make a loop
$topoafter = {
    'a' => { 'b' => 1},
    'b' => { 'c' => 1},
    'c' => { 'a' => 1},
};
$topovisited = {};
$toposorted  = [()];
my $toposortfail=0;
foreach my $c (sort keys(%$topoafter)) {
    # this is the sort init from _sortComponents
    # this does not break the finite for loop
    unless($cpl->_topoSort($c, $topoafter, $topovisited, {}, $toposorted, 1)) {
        $toposortfail = 1;
    };
}
ok($toposortfail, "toposort detected loop and returned false");

# run_all_components tested in runall.t
# executeConfigComponents / executeUnconfigComponent are tested in execute-config-components

done_testing();
