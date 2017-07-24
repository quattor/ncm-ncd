# -*- mode: cperl -*-
use strict;
use warnings;

BEGIN {
    # Ignore the ncm namespace loaded by Test::Quattor
    use Test::Quattor::Namespace;
    $Test::Quattor::Namespace::ignore->{ncm} = 1;
}

use Test::More;
use LC::Exception;
use CAF::History qw($EVENTS $REF);
use CAF::Reporter qw($HISTORY);
use CAF::Application;
use CAF::FileWriter;
use Test::MockModule;

our $this_app;

BEGIN {
    $this_app = CAF::Application->new('app', '--debug', 5);
    $this_app->{CONFIG}->define("noaction");
    $this_app->{CONFIG}->set('noaction', 1);
}

use NCM::Component;

my $mockc = Test::MockModule->new('NCM::Component');

$this_app->init_history(); # no instance tracking

my $cmp = NCM::Component->new('foo', $this_app);
my $cmp2 = NCM::Component->new('bar', $this_app);

=pod

=head1 DESCRIPTION

Tests for the C<NCM::Component> C<CAF::History> handling.

=head2 Tests for C<NCM::Component::event>

=cut

# pass the component instance as logger
my $fh = CAF::FileWriter->new('target/test/some/file', log => $cmp);
print $fh "woohoo";
$fh = undef;

diag explain $this_app->{HISTORY}->{EVENTS};

my $closeev = $this_app->{HISTORY}->{EVENTS}->[1];

is($closeev->{REF}, 'CAF::FileWriter', 'event added by FileWriter');
is($closeev->{changed}, 1, 'event of content changed FileWriter (noaction=1)');
is($closeev->{modified}, 0, 'event of unmodified FileWriter (noaction=1)');

is($closeev->{component}, 'foo', 'Component name added to metadata');
is($closeev->{component_module}, 'NCM::Component', 'Component module added to metadata');


=head2 Tests for C<NCM::Component::event_report>

=cut

my @info_msgs = ();
$mockc->mock('info', sub {shift; push(@info_msgs, join(' ', @_));} );

# same file, other component !!
$fh = CAF::FileWriter->new('target/test/some/file', log => $cmp2);
print $fh "woohoo2"; # different content
$fh = undef;

$fh = CAF::FileWriter->new('target/test/some/file2', log => $cmp2);
print $fh "woohoo2"; # different content
$fh = undef;

diag explain $this_app->{$HISTORY}->{$EVENTS};


my $closeev2 = $this_app->{$HISTORY}->{$EVENTS}->[3];

is($closeev2->{$REF}, 'CAF::FileWriter', 'event added by FileWriter by cmp2');
is($closeev2->{changed}, 1, 'event of content changed FileWriter by cmp2 (noaction=1)');
is($closeev2->{modified}, 0, 'event of unmodified FileWriter by cmp2 (noaction=1)');

is($closeev2->{component}, 'bar', 'Component name bar by cmp2');
is($closeev2->{component_module}, 'NCM::Component', 'Component module by cmp2');

# noaction=1, so nothing really modified

@info_msgs = ();
my $idx1 = $cmp->event_report();
is_deeply(\@info_msgs, [], "Nothing reported with cmp (noaction=1)");

@info_msgs = ();
my $idx2 = $cmp2->event_report();
is_deeply(\@info_msgs, [], "Nothing reported with cmp2 (noaction=1)");

# Fake noaction=0 in event history
$closeev->{modified} = 1;
$closeev2->{modified} = 1;
$this_app->{$HISTORY}->{$EVENTS}->[5]->{modified} = 1;

# test reporting by cmp
@info_msgs = ();
$idx1 = $cmp->event_report();
is_deeply(\@info_msgs,
          ["EVENT: foo modified file target/test/some/file"],
          "cmp reports 1 modified file (faked noaction=0)");
is_deeply($idx1, [1], "reported indices by cmp (faked noaction=0)");

@info_msgs = ();
$idx2 = $cmp2->event_report();
diag explain \@info_msgs;
diag explain $idx2;
is_deeply(\@info_msgs, [
    "EVENT: bar modified file target/test/some/file",
    "EVENT: bar modified file target/test/some/file2",
], "cmp2 reports 1 modified file (faked noaction=0)");
is_deeply($idx2, [3, 5], "reported indices by cmp2 (faked noaction=0)");


done_testing();
