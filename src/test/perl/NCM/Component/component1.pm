package NCM::Component::component1;

use strict;
use warnings;

use parent qw(NCM::Component);
use Readonly;
Readonly our $REDIRECT => {
    name => 'otherone',
    default => 'Regular',
};

1;
