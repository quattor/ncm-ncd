# -*- mode: cperl -*-
use strict;
use warnings;
use Test::More;
use LC::Exception;
use apphistory;
use CAF::FileReader;

our $this_app;

BEGIN {
    $this_app = apphistory->new('app');
    $this_app->{CONFIG}->define("noaction");
    $this_app->{CONFIG}->set('noaction', 1);
    $this_app->{CONFIG}->define("template-path");
    $this_app->{CONFIG}->set('template-path', "doesnotexist");
}

use NCM::Component;

$this_app->init_history(); # no instance tracking

my $cmp = NCM::Component->new('foo', $this_app);

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
my $fh = CAF::FileReader->new('/some/file', log => $cmp);
$fh = undef;

diag explain $this_app->{HISTORY}->{EVENTS};

my $closeev = $this_app->{HISTORY}->{EVENTS}->[1];

is($closeev->{REF}, 'CAF::FileReader', 'event added by FileReader');

is($closeev->{component}, 'foo', 'Component name added to metadata');
is($closeev->{component_module}, 'NCM::Component', 'Component module added to metadata');


done_testing();
