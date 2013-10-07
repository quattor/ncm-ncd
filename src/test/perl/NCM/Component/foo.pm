package NCM::Component::foo;

use strict;
use warnings;
use LC::Exception;
use parent 'NCM::Component';

our $EC = LC::Exception::Context->new()->will_store_all();

1;
