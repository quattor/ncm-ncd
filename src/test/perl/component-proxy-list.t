use strict;
use warnings;
use Test::More;
use Test::Quattor qw(component-proxy-list);
use NCD::ComponentProxyList;
use CAF::Object;
use Test::MockModule;

$CAF::Object::NoAction = 1;

our $this_app;

BEGIN {
    $this_app = CAF::Application->new('app');
    $this_app->{CONFIG}->define("state");
    $this_app->{CONFIG}->define("autodeps");
    $this_app->{CONFIG}->set('autodeps', 1);
    $this_app->{CONFIG}->define("noaction");
    $this_app->{CONFIG}->set('noaction', 1);
    $this_app->{CONFIG}->define("template-path");
    $this_app->{CONFIG}->set('template-path', "doesnotexist");
    $this_app->{CONFIG}->define("nodeps");
    $this_app->{CONFIG}->set('nodeps', 0);
}

my $cfg = get_config_for_profile('component-proxy-list');

my $mock = Test::MockModule->new('NCD::ComponentProxyList');

my $WARN = 0;
$mock->mock('warn', sub {
    $WARN++;
    diag("WARN ", join('', @_));
});

my $ERROR = 0;
$mock->mock('error', sub {
    $ERROR++;
    diag("ERROR ", join('', @_));
});

=head1

Test Init

=cut

# mock a failing _getComponents
$mock->mock('_getComponents', undef);

# no skip; random order
my @comps = qw(ee bb dd);
my $cpl = NCD::ComponentProxyList->new($cfg, undef, @comps);
isa_ok($cpl, 'NCD::ComponentProxyList', 'init returns a NCD::ComponentProxyList instance');

is_deeply($cpl->{CCM_CONFIG}, $cfg, "Configuration instance CCM_CONFIG");
is_deeply($cpl->{SKIP}, [], "Empty skip list");
is_deeply($cpl->{NAMES}, \@comps, "Correct list of initial components");

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

get_all_components

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
$mock->mock('report', sub {
    my ($self, @args) = @_;
    my $msg = join('', @args);
    push(@report, $msg);
});

$cpl->{CLIST} = \@pxs;
$cpl->reportComponents();

is_deeply(\@report, [
              'active components found inside profile /software/components:',
              'name           file?  predeps                      postdeps                     ',
              '-------------------------------------------------------------------',
              'bb:            no     aa                           cc,dd                        ',
              'cc:            no                                                               ',
              'ee:            no     aa                                                        '
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


done_testing();
