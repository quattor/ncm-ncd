use strict;
use warnings;

BEGIN {
    # Ignore the ncm namespace loaded by Test::Quattor
    use Test::Quattor::Namespace;
    $Test::Quattor::Namespace::ignore->{ncm} = 1;
}

use Test::More;
use Test::Quattor qw(component1 component-fqdn);
use Test::Quattor::Object;

# insert the this_app before load but after Test::Quattor
BEGIN {
    use CAF::Application;
    our $this_app = CAF::Application->new('app');
    $this_app->{CONFIG}->define("noaction");
    $this_app->{CONFIG}->set('noaction', 123);
}

use NCM::Component;


=head1 NoAction is set on load via this_app

=cut

is($NCM::Component::NoAction, 123, "NoAction set via this_app onload");


my $obj = Test::Quattor::Object->new();

=head1 test NCM::Component init

=cut

my $cmp1 = NCM::Component->new('component1', $obj);
isa_ok($cmp1, 'NCM::Component', 'NCM::Component instance 1 created');
is($cmp1->prefix(), "/software/components/component1", "prefix for component1");


done_testing;
