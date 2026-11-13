#!/bin/bash
>oracle.log

# ./ib phase base samples/images/oracle/ol-8.10 --follow | tee -a oracle.log
# ./ib phase base samples/images/oracle/ol-9.8 --follow | tee -a oracle.log
# ./ib phase base samples/images/oracle/ol-10.1 --follow | tee -a oracle.log

./ib phase patch samples/images/oracle/ol-8.10 --follow | tee -a oracle.log
./ib phase patch samples/images/oracle/ol-9.8 --follow | tee -a oracle.log
./ib phase patch samples/images/oracle/ol-10.1 --follow | tee -a oracle.log

./ib build samples/images/oracle/ol-8.10 --follow | tee -a oracle.log
./ib build samples/images/oracle/ol-9.8 --follow | tee -a oracle.log
./ib build samples/images/oracle/ol-10.1 --follow | tee -a oracle.log

./ib phase clean samples/images/oracle/ol-8.10 --follow
./ib phase clean samples/images/oracle/ol-9.8 --follow
./ib phase clean samples/images/oracle/ol-10.1 --follow
