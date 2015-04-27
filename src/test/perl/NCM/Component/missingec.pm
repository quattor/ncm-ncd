package NCM::Component::missingec;

use strict;
use warnings;
use LC::Exception;
use parent 'NCM::Component';

# missing package variable (should be 'our $EC')
my $EC = LC::Exception::Context->new()->will_store_all();

1;
