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

# mandatory methods

sub Configure {
    return 1;
}

sub error {
    return 1;
}

sub warn {
    return 1;
}

sub get_warnings {
    return 1;
}

sub get_errors {
    return 1;
}

sub name {
    return 1;
}

1;
