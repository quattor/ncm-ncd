use strict;
use warnings;

BEGIN {
    # Ignore the ncm namespace loaded by Test::Quattor
    use Test::Quattor::Namespace;
    $Test::Quattor::Namespace::ignore->{ncm} = 1;
}

BEGIN {
    our $TQU = <<'EOF';
[load]
modules=NCM::Check,NCM::Component,NCD::ComponentProxy,NCD::ComponentProxyList,NCD::CLI
[doc]
poddirs=target/lib/perl,target/sbin
panpaths=NOPAN
EOF
}

use Test::Quattor::Unittest;
