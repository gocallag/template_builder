#!/bin/bash
>suse.log

#./ib phase base samples/images/suse/leap-16 --follow | tee -a suse.log

./ib phase patch samples/images/suse/leap-16 --follow | tee -a suse.log

./ib build samples/images/suse/leap-16 --follow | tee -a suse.log

./ib phase clean samples/images/suse/leap-16 --follow
