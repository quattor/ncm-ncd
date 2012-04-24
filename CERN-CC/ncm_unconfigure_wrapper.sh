#!/bin/sh

if [ "$1" = "ncmunconf" ]
then
   shift
fi


/usr/sbin/ccm-fetch >>/var/log/ccm-fetch.log && \
/usr/sbin/ncm-ncd --unconfigure $1




