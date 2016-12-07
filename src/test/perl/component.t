use strict;
use warnings;

BEGIN {
    # Ignore the ncm namespace loaded by Test::Quattor
    use Test::Quattor::Namespace;
    $Test::Quattor::Namespace::ignore->{ncm} = 1;
}

use Test::More;
use Test::Quattor qw(component1 component-fqdn);
use NCM::Component;
use Test::Quattor::Object;

my $obj = Test::Quattor::Object->new();

=head1 test NCM::Component init

=cut

my $cmp1 = NCM::Component->new('component1', $obj);
isa_ok($cmp1, 'NCM::Component', 'NCM::Component instance 1 created');
is($cmp1->prefix(), "/software/components/component1", "prefix for component1");


done_testing;
