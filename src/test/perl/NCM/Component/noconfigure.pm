package NCM::Component::noconfigure;

use strict;
use warnings;
use LC::Exception;

our $EC = LC::Exception::Context->new()->will_store_all();

sub new {
    return bless {}, shift;
}

# all components require a Configure method.
# this one will not load

1;
