object template component-proxy-list;

"/software/components" = {
    # Can't have single letter components
    foreach (idx;comp; list('aa', 'bb', 'cc', 'dd', 'ee', 'ff', 'gg')) {
        SELF[comp] = create('component-structure');
    };
    SELF;
};

"/software/components/bb/dependencies/pre" = append('aa');
"/software/components/bb/dependencies/post" = append('cc');
"/software/components/bb/dependencies/post" = append('dd');
"/software/components/dd/dependencies/pre" = append('aa');
"/software/components/dd/dependencies/pre" = append('bb');
"/software/components/ee/dependencies/pre" = append('aa');

"/software/components/ff/dependencies/pre" = append('aa');
"/software/components/ff/active" = false;

# failure, ff2 can't be proxy because it's inactive
#"/software/components/ff2/active" = false;
#"/software/components/aa/dependencies/post" = append('ff2');
