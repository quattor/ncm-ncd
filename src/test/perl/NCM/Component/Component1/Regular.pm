package NCM::Component::Component1::Regular;

use strict;
use warnings;
use parent qw(NCM::Component::component1);

sub Configure
{
    return __PACKAGE__." Configure";
}

1;
