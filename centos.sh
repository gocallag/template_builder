#!/bin/bash
>centos.log
#./ib phase base samples/images/centos/centos-9.s --follow | tee -a centos.log
#./ib phase base samples/images/centos/centos-10.s --follow | tee -a centos.log

./ib phase patch samples/images/centos/centos-9.s --follow | tee -a centos.log
./ib phase patch samples/images/centos/centos-10.s --follow | tee -a centos.log

./ib build samples/images/centos/centos-9.s --follow | tee -a centos.log
./ib build samples/images/centos/centos-10.s --follow | tee -a centos.log

./ib phase clean samples/images/centos/centos-9.s --follow
./ib phase clean samples/images/centos/centos-10.s --follow
