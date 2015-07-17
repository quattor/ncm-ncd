# -*- mode: cperl -*-
use strict;
use warnings;
use Test::More;
use Test::Quattor qw(runall-comps);
use NCD::ComponentProxyList;
use NCD::ComponentProxy;
use CAF::Application;
use Test::MockModule;
use CAF::Object;

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

use Readonly;

Readonly::Hash my %INIT_GLOBAL_STATUS => {
                                          'ERRORS'   => 0,
                                          'WARNINGS' => 0
                                         };

my $mockcomponent = Test::MockModule->new("NCD::ComponentProxy");
my $mocklist = Test::MockModule->new("NCD::ComponentProxyList");

my $configure;

sub long_successful_configure
{
    my $self = shift;
    $configure++;

    if ($self->{NAME} eq 'acomponent') {
        return {ERRORS => 0, WARNINGS => 5};
    } else {
        return {ERRORS => 0, WARNINGS => 10};
    }
}

sub long_failed_configure
{
    $configure++;
    return {ERRORS => 1, WARNINGS => 0};
}

sub execute_dependency_failed
{
    my $self = shift;

    $configure++;
    is($self->{NAME}, "acomponent",
       "Components with failed dependencies are not called: $self->{NAME}");
    return {ERRORS => 1, WARNINGS => 0};
}

sub execute_failed_nodeps
{
    my $self = shift;

    $configure++;
    if ($self->{NAME} eq "acomponent") {
        return {ERRORS => 1, WARNINGS => 0};
    }
    ok(1, "Component is called even if its dependencies have failed");
    return {ERRORS => 3, WARNINGS => 5};
}

$mockcomponent->mock("executeConfigure", \&long_successful_configure);
$mocklist->mock("pre_config_actions", 1);
$mocklist->mock("post_config_actions", 1);

=pod

=head1 DESCRIPTION

Tests for the C<NCD::ComponentProxyList::run_all_components> method.

=head1 TESTS

=head2 Successful executions

=over

=item * Single component

=cut


# Initial global status
my $err = {%INIT_GLOBAL_STATUS};

my $cfg = get_config_for_profile('runall-comps');

# acomponent: no pre/post deps
# anotherone: acomponent pre dep, no post dep
# yetonemore: no pre dep, anotherone post dep
my @cmp = (NCD::ComponentProxy->new('acomponent', $cfg),
           NCD::ComponentProxy->new('anotherone', $cfg));


my $cl = NCD::ComponentProxyList->new($cfg, undef, "acomponent");

$cl->{CLIST} = [$cmp[0]];

$configure = 0;
$cl->run_all_components($cl->{CLIST}, 0, $err);

is($err->{ERRORS}, 0, "No errors reported");
is($err->{WARNINGS}, 5, "No warnings reported");
is(scalar(keys(%{$err->{WARN_COMPS}})), 1,
   "Components with warnings are reported");
is($configure, 1, "$configure components configured");

=pod

=item * Many components

=over

=item * C<$nodeps == 0>

=cut

$err = {%INIT_GLOBAL_STATUS};
$cl->{CLIST} = \@cmp;

$configure = 0;
$cl->run_all_components($cl->{CLIST}, 0, $err);
is($err->{ERRORS}, 0, "No errors detected");
is($err->{WARNINGS}, 15, "Warnings are summed up");
is(scalar(keys(%{$err->{WARN_COMPS}})), 2,
   "Components with warnings are reported");
is($configure, 2, "$configure components configured");

=pod

=item * C<$nodeps>

=back

=cut

$err = {%INIT_GLOBAL_STATUS};
$configure = 0;
$cl->run_all_components($cl->{CLIST}, 1, $err);
is($err->{ERRORS}, 0, "No errors when nodeps and all dependencies satisfied");
is($err->{WARNINGS}, 15, "Warnings correctly aggregated with nodeps");
is($configure, 2, "$configure components configured");

=pod

=back

=head2 Failed executions

=over

=item * Detect failed components

=cut

$mockcomponent->mock("executeConfigure", \&long_failed_configure);

$err = {%INIT_GLOBAL_STATUS};

$configure = 0;
$cl->run_all_components([$cmp[0]], 0, $err);
is($err->{WARNINGS}, 0, "Warnings are summed up");
is($err->{ERRORS}, 1, "All failed components are detected");
is(scalar(keys(%{$err->{ERR_COMPS}})), 1,
   "Components are added to the error list");
is($configure, 1, "$configure components configured");

=pod

=item * Detect broken dependencies

=cut

$err = {%INIT_GLOBAL_STATUS};

$mockcomponent->mock("executeConfigure", \&execute_dependency_failed);

$configure = 0;
$cl->run_all_components(\@cmp, 0, $err);
is($err->{WARNINGS}, 0, "Warnings are summed up");
is($err->{ERRORS}, 2, "Errors reported when pre-dependencies fail");
is($configure, 1, "$configure components configured");

$err = {%INIT_GLOBAL_STATUS};

$mockcomponent->mock("executeConfigure", \&execute_failed_nodeps);

$configure = 0;
$cl->run_all_components(\@cmp, 1, $err);
is($err->{WARNINGS}, 5, "Warnings are summed up");
is($err->{ERRORS}, 4, "All components get executed with --nodeps");
is($configure, 2, "$configure components configured");

# ignore-errors-from-dependencies errors of failed comp are converted in warnings
$this_app->{CONFIG}->define("ignore-errors-from-dependencies");
$this_app->{CONFIG}->set('ignore-errors-from-dependencies', 1);

$err = {%INIT_GLOBAL_STATUS};
$configure = 0;
$cl->{NAMES} = ['anotherone']; # acomponent is not requested, but is dependency via auotdeps
$cl->run_all_components(\@cmp, 1, $err);
is($err->{WARNINGS}, 6, "Warnings are summed up (one error converted in warning)");
is($err->{ERRORS}, 3, "All components get executed with --nodeps (but one error converted in warning)");
is($configure, 2, "$configure components configured");

done_testing();
