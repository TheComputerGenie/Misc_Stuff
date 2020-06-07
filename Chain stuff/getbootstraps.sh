#!/bin/bash
SHELL=/bin/sh PATH=/bin:/sbin:/usr/bin:/usr/sbin

value=`cat $HOME/komodo/src/assetchains.json`
cd $HOME/.komodo
for name in $(jq -r '.[].ac_name' <<<${value}); 
	do
		String="wget https://na.bootstrap.dexstats.info/$name-bootstrap.tar.gz"
		eval "$String"
		$(mkdir $name && tar -xzf $name-bootstrap.tar.gz --directory $HOME/.komodo/$name)
		$(rm -rf $name-bootstrap.tar.gz)
done

