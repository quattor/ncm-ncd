package NCM::Component::customcomponent;

use strict;
use warnings;
use LC::Exception;

our $EC = LC::Exception::Context->new()->will_store_all();

# by far the best component ever
# does not inherit from NCM::Component, but should load anyway

sub new {
    return bless {}, shift;
}

sub Configure {
    return 1;
}

1;
