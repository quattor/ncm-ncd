# -*- mode: cperl -*-
use strict;
use warnings;
use Test::More;
use Test::Quattor qw(trivial);
use NCD::ComponentProxyList;
use CAF::Object;
use Readonly;
use JSON::XS;

$CAF::Object::NoAction = 1;

Readonly my $PRE_HOOK => "a pre hook";
Readonly my $POST_HOOK => "a post hook";

=pod

=head1 DESCRIPTION

Tests for the C<NCD::ComponentProxyList> pre and post-configuration hooks

=head1 TESTS

=head2 No hooks specified

Succeed always.

=cut


our $this_app = CAF::Application->new('app');
$this_app->{CONFIG}->define("nodeps");
$this_app->{CONFIG}->set('nodeps', 0);

my $cfg = get_config_for_profile('trivial');

my $cl = NCD::ComponentProxyList->new($cfg, undef, "acomponent");

is($cl->pre_config_actions(), 1,
   "PRE executor succeeds when nothing is specified");
is($cl->post_config_actions(undef, undef, {}), 1,
   "POST executor succeeds when nothing is specified");

=pod

=head2 Hooks specified, without timeouts

Succeed and no timeout is passed.

=cut

is($cl->pre_config_actions($PRE_HOOK), 1, "PRE hook execution succeeds");

my $cmd = get_command($PRE_HOOK);

ok($cmd, "The pre hook is actually executed");
is($cmd->{method}, "execute", "The pre hook is execute-d");

is($cl->post_config_actions($POST_HOOK, undef, {ERRORS => 3}), 1,
   "POST hooks execution succeeds");
$cmd = get_command($POST_HOOK);
ok($cmd, "The pre hook is actually executed");
is($cmd->{method}, "execute", "The post hook is execute-d");
ok($cmd->{object}->{OPTIONS}->{stdin},
   "Something passed as stdin to the post hook");
my $json = decode_json($cmd->{object}->{OPTIONS}->{stdin});
is($json->{ERRORS}, 3, "Correct JSON object decoded");
is(scalar(keys(%$json)), 1, "Exact report object recovered");

=pod

=head2 Hooks specified, with timeouts

Check that the timeout is passed to the CAF object

=cut

is($cl->pre_config_actions($PRE_HOOK, 1), 1,
   "Timeouts don't affect exit status of the pre hook");
$cmd = get_command($PRE_HOOK);

is($cmd->{object}->{OPTIONS}->{timeout}, 1,
   "PRE Timeout passed to the underlying object");

is($cl->post_config_actions($POST_HOOK, 2, {ERRORS => 3}), 1,
   "Timeouts don't affect the exit status of the post hook");

$cmd = get_command($POST_HOOK);
is($cmd->{object}->{OPTIONS}->{timeout}, 2,
   "POST Timeout object passed to the underlying object");

=pod

=head2 Errors

Errors in executions are reported and propagated to the callers

=cut

set_command_status($PRE_HOOK, 1);
set_command_status($POST_HOOK, 1);

is($cl->pre_config_actions($PRE_HOOK), 0, "Failure in PRE hook is reported");
is($cl->post_config_actions($POST_HOOK, undef, {}), 0,
   "Failure in POST hook is reported");

done_testing();
