# -*- mode: cperl -*-
use strict;
use warnings;
use Test::More;
use LC::Exception;
use apphistory;
use CAF::FileWriter;
use Test::MockModule;

our $this_app;

BEGIN {
    $this_app = apphistory->new('app');
    $this_app->{CONFIG}->define("noaction");
    $this_app->{CONFIG}->set('noaction', 1);
    $this_app->{CONFIG}->define("template-path");
    $this_app->{CONFIG}->set('template-path', "doesnotexist");
}

use NCM::Component;

my $mockc = Test::MockModule->new('NCM::Component');

$this_app->init_history(); # no instance tracking

my $cmp = NCM::Component->new('foo', $this_app);
my $cmp2 = NCM::Component->new('bar', $this_app);

=pod

=head1 DESCRIPTION

Tests for the C<NCM::Component::add_files> and
C<NCM::Component::get_files> methods.

The tests are trivial, since the methods are just a getter and a
setter.

=cut


$cmp->add_files('/a/file', '/another/file');
my $files = $cmp->get_files();
is($files->[0], '/a/file', 'First file recorded correctly');
is($files->[1], '/another/file', 'Last file recorded correctly');
is(scalar(@$files), 2, "All files recorded correctly");

=head2 Tests for C<NCM::Component::event>

=cut

# pass the component instance as logger
my $fh = CAF::FileWriter->new('target/test/some/file', log => $cmp);
print $fh "woohoo";
$fh = undef;

diag explain $this_app->{HISTORY}->{EVENTS};

my $closeev = $this_app->{HISTORY}->{EVENTS}->[1];

is($closeev->{REF}, 'CAF::FileWriter', 'event added by FileWriter');
is($closeev->{modified}, 1, 'event of modified FileWriter');

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

diag explain $this_app->{HISTORY}->{EVENTS};


$closeev = $this_app->{HISTORY}->{EVENTS}->[3];

is($closeev->{REF}, 'CAF::FileWriter', 'event added by FileWriter by cmp2');
is($closeev->{modified}, 1, 'event of modified FileWriter by cmp2');

is($closeev->{component}, 'bar', 'Component name bar by cmp2');
is($closeev->{component_module}, 'NCM::Component', 'Component module by cmp2');


# test reporting by cmp
@info_msgs = ();
my $idx1 = $cmp->event_report();
is_deeply(\@info_msgs,
          ["EVENT: modified file target/test/some/file"],
          "cmp reports 1 modified file");
is_deeply($idx1, [1], "reported indices by cmp");

@info_msgs = ();
my $idx2 = $cmp2->event_report();
diag explain \@info_msgs;
diag explain $idx2;
is_deeply(\@info_msgs, [
    "EVENT: modified file target/test/some/file",
    "EVENT: modified file target/test/some/file2",
], "cmp2 reports 1 modified file");
is_deeply($idx2, [3, 5], "reported indices by cmp2");


done_testing();
