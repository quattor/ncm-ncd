#!/bin/sh


if [ "$1" = "ncm" ]
then
   shift
   [ "$NOTD_EXEC_TODO" != 'boot' ] && perl -e 'sleep rand 240'
fi

if [ "$1x" = "x" ] ; then
   args="--all" ;
else
   args=$* ;
fi
   
/usr/sbin/ccm-fetch >>/var/log/ccm-fetch.log && \
/usr/sbin/ncm-ncd --configure $args




