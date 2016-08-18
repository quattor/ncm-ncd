package NCM::Component::foo;

use strict;
use warnings;

use version;

use LC::Exception;
use parent 'NCM::Component';

our $EC = LC::Exception::Context->new()->will_store_all();

our $VERSION = version->new("v1.2.3");

1;
