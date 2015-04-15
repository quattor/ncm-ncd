package NCM::Component::brokennew;

use strict;
use warnings;
use LC::Exception;

# Needs to hav a new method, ideally via NCM::Component inheritance
#use parent 'NCM::Component';

our $EC = LC::Exception::Context->new()->will_store_all();

1;
