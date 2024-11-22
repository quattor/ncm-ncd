package NCM::Component::Component1::Subby;

use strict;
use warnings;
use parent qw(NCM::Component::component1);


sub Unconfigure
{
    return __PACKAGE__." Unconfigure";
}

1;
