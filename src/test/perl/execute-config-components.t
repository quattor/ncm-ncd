# -*- mode: cperl -*-
use strict;
use warnings;
use Test::More;
use Test::Quattor qw(execute-config-components execute-config-deps);
use NCD::ComponentProxyList;
use NCD::ComponentProxy;
use CAF::Application;
use Test::MockModule;
use CAF::Object;

$CAF::Object::NoAction = 1;

my $mockcomponent = Test::MockModule->new("NCD::ComponentProxy");
my $mocklist = Test::MockModule->new("NCD::ComponentProxyList");

sub long_successful_configure
{
    my $self = shift;

    if ($self->{NAME} eq 'acomponent') {
        return {ERRORS => 0, WARNINGS => 5};
    } else {
        return {ERRORS => 0, WARNINGS => 10};
    }
}

sub long_failed_configure
{
    return {ERRORS => 1, WARNINGS => 0};
}

sub execute_dependency_failed
{
    my ($self) = shift;

    is($self->{NAME}, "acomponent",
       "Components with failed dependencies are not called: $self->{NAME}");
    return {ERRORS => 1, WARNINGS => 0};
}

$mockcomponent->mock("executeConfigure", \&long_successful_configure);
$mocklist->mock("pre_config_actions", 1);
$mocklist->mock("post_config_actions", 1);

=pod

=head1 DESCRIPTION

Tests for the C<NCD::ComponentProxyList::executeConfigComponents>
method.

=head1 TESTS

=head2 Successful executions

=over

=item * Single component

=cut


our $this_app = CAF::Application->new('app');
$this_app->{CONFIG}->define("nodeps");
$this_app->{CONFIG}->set('nodeps', 0);

my $cfg = get_config_for_profile('execute-config-components');


my $cl = NCD::ComponentProxyList->new($cfg, undef, "acomponent");

#$cl->{CLIST} = [NCD::ComponentProxy->new('acomponent', $cfg)];

my $err = $cl->executeConfigComponents();

is($err->{ERRORS}, 0, "No errors reported");
is($err->{WARNINGS}, 5, "No warnings reported");
is(scalar(keys(%{$err->{WARN_COMPS}})), 1,
   "Component with warnings are reported");


=pod

=item * Many components

=cut

$cl = NCD::ComponentProxyList->new($cfg, undef, "acomponent", "anotherone");

$err = $cl->executeConfigComponents();
is($err->{ERRORS}, 0, "No errors detected");
is($err->{WARNINGS}, 15, "Warnings are summed up");
is(scalar(keys(%{$err->{WARN_COMPS}})), 2,
   "Components with warnings are reported");

=pod

=back

=head2 Failed executions

=over

=item * Detect failed components

=cut

$mockcomponent->mock("executeConfigure", \&long_failed_configure);

$err = $cl->executeConfigComponents();
is($err->{ERRORS}, 2, "All failed components are detected");
is(scalar(keys(%{$err->{ERR_COMPS}})), 2,
   "Components are added to the error list");

=pod

=item * Detect broken dependencies

=cut

$mockcomponent->mock("executeConfigure", \&execute_dependency_failed);

$cfg = get_config_for_profile("execute-config-deps");

$cl = NCD::ComponentProxyList->new($cfg, undef, "acomponent", "anotherone");

$err = $cl->executeConfigComponents();
is($err->{ERRORS}, 2, "Errors reported when pre-dependencies fail");


=pod

=back

=head2 Hooks

We have already tested when there are no hooks or they succeed.  Now
we must test what happens if the hooks fail

=over

=item * Post-config hook fails

=back

=cut

$mocklist->mock("post_config_actions", 0);

$err = $cl->executeConfigComponents();
is($err->{ERRORS}, 3, "Errors on post_config hooks are reported");

$mocklist->mock("pre_config_actions", 0);
$mockcomponent->mock("executeConfigure", sub {
                         ok(0, "This method shouldn't be called at this stage");
                         return {ERRORS => 0, WARNINGS => 0};
                     });

$err = $cl->executeConfigComponents();
is($err->{ERRORS}, 1, "If pre_config hook fails no components are executed");


done_testing();
