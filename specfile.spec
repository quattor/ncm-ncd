Summary: @DESCR@
Name: @NAME@
Version: @VERSION@
Vendor: EDG / CERN
Release: @RELEASE@
License: http://www.eu-datagrid.org/license.html
Group: @GROUP@/System
Source: @TARFILE@
BuildArch: noarch
BuildRoot: /var/tmp/%{name}-build
Packager: @AUTHOR@
URL: @QTTR_URL@

Requires: perl-CAF >= 1.6.5
Requires: perl-LC
Requires: ccm >= 1.1.6
Requires: ncm-template >= 1.0.8

%description
@DESCR@


%prep
%setup

%build
make

%install
rm -rf $RPM_BUILD_ROOT
make PREFIX=$RPM_BUILD_ROOT install

# leave log file//
#%postun
#[ $1 = 0 ] && rm -f @NCM_ROTATED@/@NAME@
#exit 0

%files
%defattr(-,root,root)
@QTTR_SBIN@/@COMP@
@QTTR_PERLLIB@/NCD/
@QTTR_PERLLIB@/NCM/
@QTTR_ROTATED@/@COMP@
@QTTR_LOCKD@/
@NCM_COMP_TMP@/
@NCM_LOG@/
%doc @QTTR_DOC@/
%doc @QTTR_MAN@/man@MANSECT@/@COMP@.@MANSECT@.gz
%doc @QTTR_MAN@/man@NCM_MANSECT@/NCM::Component.@NCM_MANSECT@.gz
%doc @QTTR_MAN@/man@NCM_MANSECT@/NCM::Check.@NCM_MANSECT@.gz
%doc @QTTR_MAN@/man@NCM_MANSECT@/NCM::HLConfig.@NCM_MANSECT@.gz
%config @QTTR_ETC@/@COMP@.conf
%attr(755,root,root) @QTTR_SBIN@/ncm_wrapper.sh
%attr(755,root,root) @QTTR_SBIN@/ncm_unconfigure_wrapper.sh
%dir /var/run/quattor-components

%package -n CERN-CC-ncm-ncd-notd
Group: @GROUP@/System
Summary: NCM-NCD: CERN-CC specific entries for not.d
Requires: ncm-ncd 
%description -n CERN-CC-ncm-ncd-notd
NCM-NCD: CERN-CC specific entries for not.d 

%files -n CERN-CC-ncm-ncd-notd
%defattr(-,root,root)
%config @QTTR_ETC@/not.d/ncm
%config @QTTR_ETC@/not.d/ncm_unconf

%clean
rm -rf $RPM_BUILD_ROOT
