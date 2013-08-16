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

my $mock = Test::MockModule->new("NCD::ComponentProxy");


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

$mock->mock("executeConfigure", \&long_successful_configure);

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

$mock->mock("executeConfigure", \&long_failed_configure);

$err = $cl->executeConfigComponents();
is($err->{ERRORS}, 2, "All failed components are detected");
is(scalar(keys(%{$err->{ERR_COMPS}})), 2,
   "Components are added to the error list");

=pod

=item * Detect broken dependencies

=cut

$mock->mock("executeConfigure", \&execute_dependency_failed);

$cfg = get_config_for_profile("execute-config-deps");

$cl = NCD::ComponentProxyList->new($cfg, undef, "acomponent", "anotherone");

$err = $cl->executeConfigComponents();
is($err->{ERRORS}, 2, "Errors reported when pre-dependencies fail");


done_testing();
