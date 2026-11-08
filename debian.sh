#!/bin/bash
>debian.log

#./ib phase base samples/images/debian/debian-13 --follow | tee -a debian.log
./ib phase patch samples/images/debian/debian-13 --follow | tee -a debian.log
./ib build samples/images/debian/debian-13 --follow | tee -a debian.log
./ib phase clean samples/images/debian/debian-13 --follow
