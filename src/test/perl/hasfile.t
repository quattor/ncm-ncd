# -*- mode: cperl -*-
use strict;
use warnings;

BEGIN {
    # Ignore the ncm namespace loaded by Test::Quattor
    use Test::Quattor::Namespace;
    $Test::Quattor::Namespace::ignore->{ncm} = 1;
}

use Test::More;
use CAF::Object;
use LC::Exception;
use NCD::ComponentProxy;
use Readonly;

Readonly my $BASE => "./src/test/perl/NCM/Component/";

my $cmp = {
    NAME => "foo",
    MODULE => "idonotexist"
   };
bless($cmp, "NCD::ComponentProxy");

=pod

=head1 DESCRIPTION

Tests for the C<NCD::ComponentProxy::hasFile> method

=head1 TESTS

=over

=item * The file does not exist

=cut

ok(!$cmp->hasFile($BASE), "Non-existing module not found");

=pod

=item * The file exists

=back

=cut

$cmp->{MODULE} = "spma::ips";

ok($cmp->hasFile($BASE), "Component spma::ips found");

$cmp->{MODULE} = "foo";
ok($cmp->hasFile($BASE), "Non-namespaced component foo found");

done_testing();
