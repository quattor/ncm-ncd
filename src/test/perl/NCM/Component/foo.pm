package NCM::Component::foo;

use strict;
use warnings;

use version;

BEGIN {
    # Insert something in the environment
    $ENV{TEST_COMPONENTPROXY} = 'a test';
}

use LC::Exception;
use parent 'NCM::Component';

our $EC = LC::Exception::Context->new()->will_store_all();

our $VERSION = version->new("v1.2.3");

sub Configure
{
    my ($self, $config) = @_;

    # for unittests
    # 2 warns, 3 errors
    $self->warn("foo Configure w1");
    $self->warn("foo Configure w2");
    $self->error("foo Configure e1");
    $self->error("foo Configure e2");
    $self->error("foo Configure e3");

    $self->{_config} = $config;
    $self->{_active_config} = $self->{ACTIVE_CONFIG};

    return 1;
};

1;
