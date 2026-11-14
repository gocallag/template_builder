#!/bin/bash
>redhat.log

# ./ib phase base samples/images/redhat/rhel-8.10 --follow | tee -a redhat.log
# ./ib phase base samples/images/redhat/rhel-9.9 --follow | tee -a redhat.log
# ./ib phase base samples/images/redhat/rhel-10.3 --follow | tee -a redhat.log

./ib phase patch samples/images/redhat/rhel-8.10 --follow | tee -a redhat.log
./ib phase patch samples/images/redhat/rhel-9.9 --follow | tee -a redhat.log
./ib phase patch samples/images/redhat/rhel-10.3 --follow | tee -a redhat.log

./ib build samples/images/redhat/rhel-8.10 --follow | tee -a redhat.log
./ib build samples/images/redhat/rhel-9.9 --follow | tee -a redhat.log
./ib build samples/images/redhat/rhel-10.3 --follow | tee -a redhat.log

./ib phase clean samples/images/redhat/rhel-8.10 --follow
./ib phase clean samples/images/redhat/rhel-9.9 --follow
./ib phase clean samples/images/redhat/rhel-10.3 --follow
