# -*- mode: cperl -*-
use strict;
use warnings;
use Test::More;
use LC::Exception;
use CAF::Application;

our $this_app;

BEGIN {
    $this_app = CAF::Application->new('app');
}

use NCM::Component;

=pod

=head1 DESCRIPTION

Tests for the C<NCM::Component::add_files> and
C<NCM::Component::get_files> methods.

The tests are trivial, since the methods are just a getter and a
setter.

=cut

my $cmp = NCM::Component->new('foo', $this_app);

$cmp->add_files('/a/file', '/another/file');
my $files = $cmp->get_files();
is($files->[0], '/a/file', 'First file recorded correctly');
is($files->[1], '/another/file', 'Last file recorded correctly');
is(scalar(@$files), 2, "All files recorded correctly");

done_testing();
