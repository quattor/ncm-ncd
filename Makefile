####################################################################
# Distribution Makefile
####################################################################

.PHONY: configure install clean

all: configure

#
# BTDIR needs to point to the location of the build tools
#
BTDIR := quattor-build-tools
#
#
_btincl   := $(shell ls $(BTDIR)/quattor-buildtools.mk 2>/dev/null || \
             echo quattor-buildtools.mk)
include $(_btincl)

CERN_CC_SOURCES = ncm.notd ncm_unconf.notd ncm_wrapper.sh ncm_unconfigure_wrapper.sh

LIBFILES = NCM/Component NCM/HLConfig NCM/Check NCD/ComponentProxy NCD/ComponentProxyList

####################################################################
# Configure
####################################################################

configure: $(COMP) $(addsuffix .pm,$(LIBFILES)) \
           $(addprefix CERN-CC/,$(CERN_CC_SOURCES))


####################################################################
# Install
####################################################################

install: configure man
	@echo installing ...
	@mkdir -p $(PREFIX)/$(QTTR_SBIN)
	@mkdir -p $(PREFIX)/$(QTTR_ETC)
	@mkdir -p $(PREFIX)/$(QTTR_MAN)/man$(NCM_MANSECT)
	@mkdir -p $(PREFIX)/$(QTTR_PERLLIB)/NCD
	@mkdir -p $(PREFIX)/$(QTTR_PERLLIB)/NCM
	@mkdir -p $(PREFIX)/$(QTTR_ROTATED)
	@mkdir -p $(PREFIX)/$(QTTR_LOCKD)
	@mkdir -p $(PREFIX)/$(NCM_LOG)
	@mkdir -p $(PREFIX)/$(NCM_COMP_TMP)
	@mkdir -p $(PREFIX)/$(NCM_COMP)
	@mkdir -p $(PREFIX)/$(QTTR_DOC)
	@mkdir -p $(PREFIX)/$(QTTR_MAN)/man1
	@mkdir -p $(PREFIX)/$(QTTR_ETC)/not.d
	@mkdir -p $(PREFIX)/$(QTTR_VAR)/run/quattor-components

	@install -m 0755 $(COMP) $(PREFIX)/$(QTTR_SBIN)/$(COMP)
	@install -m 0444 $(COMP).conf $(PREFIX)/$(QTTR_ETC)/$(COMP).conf
	@install -m 0444 $(COMP).logrotate $(PREFIX)/$(QTTR_ROTATED)/ncm-ncd
	@install -m 0544 CERN-CC/ncm.notd $(PREFIX)/$(QTTR_ETC)/not.d/ncm
	@install -m 0544 CERN-CC/ncm_unconf.notd $(PREFIX)/$(QTTR_ETC)/not.d/ncm_unconf
	@install -m 0755 CERN-CC/ncm_wrapper.sh $(PREFIX)/$(QTTR_SBIN)/ncm_wrapper.sh
	@install -m 0755 CERN-CC/ncm_unconfigure_wrapper.sh $(PREFIX)/$(QTTR_SBIN)/ncm_unconfigure_wrapper.sh

	@for i in $(LIBFILES) ; do \
		install -m 0555 $$i.pm \
			$(PREFIX)/$(QTTR_PERLLIB)/$$i.pm ; \
	done


	@install -m 0444 $(COMP).$(MANSECT).gz \
	                 $(PREFIX)$(QTTR_MAN)/man$(MANSECT)/$(COMP).$(MANSECT).gz
	@install -m 0444 NCM::Component.$(NCM_MANSECT).gz $(PREFIX)/$(QTTR_MAN)/man$(NCM_MANSECT)/NCM::Component.$(NCM_MANSECT).gz
	@install -m 0444 NCM::Check.$(NCM_MANSECT).gz $(PREFIX)/$(QTTR_MAN)/man$(NCM_MANSECT)/NCM::Check.$(NCM_MANSECT).gz
	@install -m 0444 NCM::HLConfig.$(NCM_MANSECT).gz $(PREFIX)/$(QTTR_MAN)/man$(NCM_MANSECT)/NCM::HLConfig.$(NCM_MANSECT).gz
	@for i in LICENSE MAINTAINER ChangeLog README ; do \
		install -m 0444 $$i $(PREFIX)/$(QTTR_DOC)/$$i ; \
		install -m 0444 $(COMP).conf \
			   $(PREFIX)/$(QTTR_DOC)/$(COMP).conf.example ; \
	done


man: configure
	@pod2man $(_podopt) $(COMP) >$(COMP).1
	@pod2man $(_podopt) NCM/Component.pm >NCM::Component.$(NCM_MANSECT)
	@pod2man $(_podopt) NCM/Check.pm >NCM::Check.$(NCM_MANSECT)
	@pod2man $(_podopt) NCM/HLConfig.pm >NCM::HLConfig.$(NCM_MANSECT)
	@gzip -f $(COMP).1 NCM::Component.$(NCM_MANSECT) \
                 NCM::Check.$(NCM_MANSECT) NCM::HLConfig.$(NCM_MANSECT)


####################################################################


clean::
	@echo cleaning $(NAME) files ...
	@rm -f $(COMP) $(COMP).pod $(NAME).$(NCM_MANSECT) \
		$(addsuffix .pm,$(LIBFILES)) $(addprefix CERN-CC/,$(CERN_CC_SOURCES))
	@rm -rf TEST


