# ${license-info}
# ${developer-info
# ${author-info}
# ${build-info}

package NCM::HLConfig;
use parent qw(Exporter);

# Only make callable functions visible externally
our @EXPORT_OK = qw($SOURCE %SchemaMap CreateSub Profile_URL);

use DBI;
use Sys::Hostname;


# Global variables
$cdbcfg = undef;
$cm = undef;
$ec = undef;    # Error Context for CDB code
$xml_loaded = "NULL";
$xmltree = undef;
$LOCKED_CONFIG = 0;

our $DEBUG;
$DEBUG = 0;


%SchemaMap =
    (
     SerialNumber    => "/hardware/serialnumber",
     Vendor          => "/hardware/vendor",
     CPUs            => "/hardware/cpus",
     Memory          => "/hardware/ram/0/size",
     HardDisks       => "/hardware/harddisks",
     HWaddress       => "/hardware/cards/nic/0/hwid",
     Location        => "/hardware/location",
     Type            => "/system/cluster/type",
     Contract        => "/system/contract",
     RootMail        => "/system/rootmail",
     SiteRelease     => "/system/siterelease",
     IPaddress       => "/system/network/interfaces/eth0/ip",
     Netmask         => "/system/network/interfaces/eth0/netmask",
     Gateway         => "/system/network/interfaces/eth0/gateway",
     TimeServer      => "/system/network/timeserver",
     NameServer      => "/system/network/nameserver",
     Kernel          => "/system/kernel/version",
     Partitions      => "/system/filesystems",
     Packages        => "/software/packages",
     Repositories    => "/software/repositories",
     NetDriver       => "/system/network/interfaces",
     Cluster         => "/system/cluster/name",
    );

my @specific = qw(ComponentActive Partitions Repositories NetDriver Packages);
push(@EXPORT_OK,@specific);

my %subs = %SchemaMap;
for my $sub (keys %subs){
    delete $subs{$sub} if grep {$sub eq $_} @specific;
}

&CreateSub(%subs);


#+++############################################################################
#                                                                              #
# Set of functions to parse, and load into a hash the info from the CCM        #
#  Relies on global variables $ec and $cm to avoid reloading unnecessarily     #
#                                                                              #
#---############################################################################
sub InitialiseCDB () {
    my $ret = undef;
    my $cache_dir = undef;
    my $config = undef;
    my $cred = undef;    # Fake credentials :)
    # Trick to load only at run time - allowing graceful failure
    if ( eval "require EDG::WP4::CCM::CacheManager" && eval "require LC::Exception") {
        unless (defined $ec) {    # instantiate exception context if not already done
            $ec = LC::Exception::Context->new();
            $ec->will_store_errors();
        }
        if (not defined $cm) {
            if (defined $cache_dir) {
                $cm = EDG::WP4::CCM::CacheManager->new($cache_dir);
                #croak "CDB cache directory ($cache_dir) access failed" if not $cm;
            } else {
                $cm = EDG::WP4::CCM::CacheManager->new();
                #croak "CDB cache directory (default) access failed" if not $cm;
            }
        }
        if (defined $cm) {
            if ($LOCKED_CONFIG > 1) {  # The ConfigID is passed via the LOCKED_CONFIG global flag
                $config = $cm->getLockedConfiguration($cred, $LOCKED_CONFIG);
                #croak "CDB configuration ($LOCKED_CONFIG) access failed" if not $config;
            } else {
                $config = $cm->getLockedConfiguration($cred);
                #croak "CDB configuration (latest) access failed" if not $config;
            }
            $ec->ignore_error() if not $config;
        } else {
            $ec->ignore_error();
        }
    }
    return $config;
}
sub LoadSubTreeCDB ($) {
    my $t = shift;    # Sub Tree pointer
    my $ret = undef;
    my ($el, $el_name);
    if ($t->isProperty()) {
        $ret = $t->getValue();    # Simple leaf value
    } else {
        while($t->hasNextElement()) {
            $el = $t->getNextElement();
            $el_name = $el->getName();
            if ($el_name =~ /^[0-9]$/) {
                push(@$ret, &LoadSubTreeCDB($el));
            } else {
                ${$ret}{$el_name} = &LoadSubTreeCDB($el);
            }
        }
    }
    return $ret;
}
sub ReleaseCDBLock () {
    $cdbcfg->unlock();
}
sub LoadFromCDB ($) {
    #my $host = shift;
    my $sa = shift;    # schema address
    my %kvp = ();
    return if not defined $sa;
    unless ($LOCKED_CONFIG and defined $cdbcfg) {
        $cdbcfg = InitialiseCDB();
    }
    if (defined $cdbcfg) {
        unless ($b = $cdbcfg->getElement($sa)) {
            $ec->ignore_error();  # Element not found
        } else {
            $r = LoadSubTreeCDB($b);  # Element found, load it
            return $r;
        }
        if (not $LOCKED_CONFIG) {
            unless ($cdbcfg->unlock()) {
                $ec->ignore_error();  # Wasn't locked
            }
        }
    }
    return undef;
}

#+++############################################################################
#                                                                              #
# Set of functions to download, parse, and load into a hash the XML            #
#                                                                              #
#---############################################################################
sub InitialiseXML ($) {
    my $host = shift;
    my $ret = undef;
    my $url = $Profile_URL;
    $url =~ s/%%HOSTNAME%%/$host/g;
    # Trick to load only at run time - allowing graceful failure
    if ( eval "require LWP::Simple" && eval "require XML::Parser" ) {
        my $xmlcontent = LWP::Simple::get($url);
        return undef if not $xmlcontent;  # No XML available - give up!
        # Parse the XML content into a tree
        my $xp = new XML::Parser(Style => 'Tree');
        $ret = eval { $xp->parse($xmlcontent); };
        #croak "XML content parse failed: $@\n" if $@;
        $ret = undef if $@;
    }
    return $ret;
}
sub NavigateToXML {
    my $t = shift;    # Array to scan
    my @tla = @_;    # Tag list array
    my $ret = undef;
    my $index = -1;
    if (ref($t) eq "ARRAY") {    # Passed an array to scan
        my $inti = (ref($t->[0]) eq "HASH") ? 1 : 0;    # Ignore an attribute hash as it refers to parent
        for (my $i=$inti; $i<scalar @$t; $i+=2) {
            my $tag = $t->[$i];
            my $con = $t->[$i+1];
            if (not ref($con)) {
                next;
            } elsif (ref($con->[0]) eq "HASH" and defined(${$con->[0]}{name})) {
                my %atr = %{$con->[0]}; # Name given in atribute hash (stored one level down)
                if ($atr{name} eq $tla[0]) {
                    if (scalar @tla == 1) {
                        $ret = $con;
                    } else {
                        shift(@tla);
                        $ret = &NavigateToXML($con,@tla);
                    }
                    last;
                }
            } else {    # Un-named items considered as list
                $index++;
                if ($index == $tla[0]) {
                    if (scalar @tla == 1) {
                        $ret = $con;
                    } else {
                        shift(@tla);
                        $ret = &NavigateToXML($con,@tla);
                    }
                    last;
                }
            }
        }
    }
    return $ret;
}
sub LoadSubTreeXML ($) {
    my $t = shift;    # Array to scan
    my $ret = undef;
    if (ref($t) eq "ARRAY") {    # Passed an array to scan
        my $inti = (ref($t->[0]) eq "HASH" ? 1 : 0);    # Ignore an attribute hash as it refers to parent
        for (my $i=$inti; $i<scalar @$t; $i+=2) {
            my $tag = $t->[$i];
            my $con = $t->[$i+1];
            if (not ref($con) and $con !~ /[\n]/) {
                $ret = $con;    # Simple leaf value
                last;
            } elsif (not ref($con)) {
                next;    # Some garbage, not fully sure what!
            } elsif (ref($con->[0]) eq "HASH" and defined ${$con->[0]}{name}){
                my %atr = %{$con->[0]}; # Name given in atribute hash (stored one level down)
                ${$ret}{$atr{name}} = &LoadSubTreeXML($con) if $atr{name};
            } else {    # Un-named items considered as list
                push(@$ret, &LoadSubTreeXML($con));
            }
        }
    }
    return $ret;
}
sub ReleaseXMLLock () {
    $xml_loaded = "NULL";
}
sub LoadFromXML ($$) {
    my $host = shift;
    my $sa = shift;    # schema address
    my %kvp = ();
    unless ($LOCKED_CONFIG and ($xml_loaded eq $host)) {
        $xmltree = InitialiseXML($host);
        $xml_loaded = $host;
    }
    if (ref($xmltree) eq "ARRAY") {
        my @tla = split(/\//,$sa);
        $tla[0] = "profile"; # Overwrite the dummy first array element
        my $b = NavigateToXML($xmltree,@tla);
        $r = LoadSubTreeXML($b);
        return $r;
    }
    return undef;
}

#+++############################################################################
#                                                                              #
# Download the requests Values, trying first CDB, then XML                     #
#                                                                              #
#---############################################################################
sub DownloadValue ($$) {
    my ($host, $key) = @_;
    my %kvp;
    my @sa;
    map {$kvp{$_} = undef} keys %SchemaMap;
    # Establish which quantities are being looked for
    if (grep {$_ eq $key} keys %SchemaMap) {
        @sa = $key;
    } elsif ($key eq "ALL") {
        push(@sa,keys %SchemaMap);
    } else {
        print STDERR "Unknown KEY requested: \"$key\"\n";
        return undef;
    }

    $SOURCE = "   ";
    # Search the tree for the required quantities
    my $hostname = hostname();
    $hostname =~ s/\..*//;
    $host     =~ s/\..*//;
    foreach $a (@sa) {
        # First try CDB, if installed on the client, and if run as root
        if ($host eq $hostname and $< == 0) {
            $kvp{$a} = LoadFromCDB($SchemaMap{$a});
            $SOURCE = "CCM";
        }
        # Next try to download the XML file via HTTP, if an XML profile exists for it
        if ($Profile_URL and not defined $kvp{$a} and defined $SchemaMap{$a}) {
            $kvp{$a} = LoadFromXML($host,$SchemaMap{$a});
            $SOURCE = "XML";
        }
        $SOURCE = "   " if not defined $kvp{$a};
    }
    %kvp;
}
sub LockConfig {
    my $cid = shift;
    $LOCKED_CONFIG = (defined $cid ? $cid : 1);
}
sub UnLockConfig {
    ReleaseCDBLock();
    ReleaseXMLLock();
    $LOCKED_CONFIG = 0;
}

#+++############################################################################
#                                                                              #
# Generic return function - Key as argument (Optional hostname)                #
#                                                                              #
#---############################################################################
sub Value {
    my ($key, $host) = @_;
    $host ||= hostname();
    $host =~ s/\..*//;
    # Check it is a key we can respond to
    if (not grep {$_ eq $key} keys %SchemaMap) {
        print STDERR "Unknown Key requested \"$key\"\n";
        return undef;
    }
    my %kvp = DownloadValue($host, $key);
    return $kvp{$key};
}

#+++############################################################################
#                                                                              #
# Generic return function - All known values as a hash                         #
#                                                                              #
#---############################################################################
sub Values {
    my $host = $_[0] || hostname();
    $host =~ s/\..*//;
    my %kvp = DownloadValue($host, "ALL");
    $SOURCE = "   ";    # A single value has no meaning on multiple downloads
    return %kvp;
}

#+++############################################################################
#                                                                              #
# Return functions - One per key name                                          #
#   Dynamically create all the necessary entry point functions in order        #
#   to reuse the same code                                                     #
#                                                                              #
#---############################################################################

sub CreateSub{
    my %schema = @_;
    while (my ($name,$entry) = each %schema){
        #print "$name,$entry\n";
        $SchemaMap{$name} = $entry if not $SchemaMap{$name};
        *$name = sub {
            my $host = $_[0] || hostname();
            $host =~ s/\..*//;
            my $key = $name;
            my %kvp = DownloadValue($host,$key);
            if (ref($kvp{$key}) eq "ARRAY") {
                return @{$kvp{$key}};
            } elsif (ref($kvp{$key}) eq "HASH") {
                return %{$kvp{$key}};
            } elsif (defined $kvp{$key}) {
                return $kvp{$key};
            }
            if (wantarray()){
                return ();
            }elsif (defined wantarray()){
                return undef;
            }else{
                return;
            }
        }
    }
}
sub ParameterDump { # This is a user steered function
    my $fram = $_[0]; # Should specify features or components
    my $comp = $_[1];
    my $host = $_[2] || hostname();
    $host =~ s/\..*//;
    my %ret = DownloadValue($host,$fram);
    if (ref($ret{$fram}{$comp}) eq "ARRAY") {
        return @{$ret{$fram}{$comp}};
    } elsif (ref($ret{$fram}{$comp}) eq "HASH") {
        return %{$ret{$fram}{$comp}};
    } elsif (defined $ret{$fram}{$comp}) {
        return $ret{$fram}{$comp};
    }
    if (wantarray()){
        return ();
    }elsif (defined wantarray()){
        return undef;
    }else{
        return;
    }
}
sub ComponentActive {
    my $comp = $_[0];
    my $host = $_[1] || hostname();
    $host =~ s/\..*//;
    my %ret = DownloadValue($host,"/software/components");
    return undef if not defined $ret{components}{$comp};
    return $ret{components}{$comp}{active};
}
sub Packages{
    my $host = $_[0] || hostname();
    $host =~ s/\..*//;
    my %kvp = DownloadValue($host,"Packages");
    return %{$kvp{Packages}};
}

sub Repositories {
    my $host = $_[0] || hostname();
    $host =~ s/\..*//;
    my %ret = DownloadValue($host,"Repositories");
    my %kvp = ();
    for my $r (@{$ret{Repositories}}) {
        my $name = ${$r}{name};
        for my $p (@{${$r}{protocols}}) {
            my $protocol = ${$p}{name};
            #$protocol =~ s/(\w+):.*/$1/;
            $kvp{$name}{$protocol} = ${$p}{url};
        }
    }
    return %kvp;
}
sub NetDriver {
    my $host = $_[0] || hostname();
    $host =~ s/\..*//;
    my %ret = DownloadValue($host,"NetDriver");
    my %kvp = ();
    %ret = %{$ret{NetDriver}};
    for my $if (keys %ret) {
        $kvp{$if} = $ret{$if}{driver} if defined $ret{$if}{driver};
    }
    return %kvp;
}
sub LBClusters {
    my @LBclusters = ();
    my %ret = DownloadValue("loadbalancer","lbclusters");
    for my $key (sort keys %{$ret{lbclusters}}){
        push(@LBclusters,$key);
    }
    return @LBclusters;
}
sub LBParameters {
    my $clus = $_[0];
    my %ret = DownloadValue("loadbalancer","lbclusters");
    my $rt = ${$ret{lbclusters}}{$clus};
    if (defined $rt && ref($rt) eq "HASH") {
        return %{$rt};
    }
    return undef;
}

return 1;

__END__

###################################################################
#####   Perldoc-umentation


=head1 NAME

NCM::HLConfig.pm - High Level API library to machine Configuration parameters

=head1 SYNOPSIS

Direct Access functions:
    NCM::HLConfig::Cluster( [<machine>] )
    NCM::HLConfig::Type( [<machine>] )
    NCM::HLConfig::Contract( [<machine>] )
    NCM::HLConfig::CCDBName( [<machine>] )
    NCM::HLConfig::LSFCluster( [<machine>] )
    NCM::HLConfig::IPaddress( [<machine>] )
    NCM::HLConfig::HWaddress( [<machine>] )
    NCM::HLConfig::Location( [<machine>] )
    NCM::HLConfig::Gateway( [<machine>] )
    NCM::HLConfig::Netmask( [<machine>] )
    NCM::HLConfig::TimeServer( [<machine>] )
    NCM::HLConfig::NameServer( [<machine>] )
    NCM::HLConfig::CPUs( [<machine>] )
    NCM::HLConfig::Memory( [<machine>] )
    NCM::HLConfig::HardDisks( [<machine>] )  returns hash (keys hd{a|b|c|d})
    NCM::HLConfig::Repositories( [<machine>] )
    NCM::HLConfig::Packages( [<machine>] )

    NCM::HLConfig::ClusterMembers( <clusters> )
              ClusterMembers( {type   => "interactive",
                               system => "redhat732"}  ,  <clusters> )
              ClusterMembers( {system => [("redhat61","redhat73","redhat732")]}  ,  <clusters> )
                       where allowed types and systems correspond to their BIS values


=head1 DESCRIPTION

C<NCM::HLConfig> functions return all configuration parameters for the calling host, or
optionally another I<machine>, deriving the information from CDB configuration database.

=head1 AUTHORS

  Tim Smith <Tim.Smith@cern.ch>
  Jan van Eldik <Jan.van.Eldik@cern.ch>
