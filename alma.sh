#!/bin/bash
>alma.log

#./ib phase base samples/images/almalinux/almalinux-8.10 --follow | tee -a alma.log
./ib phase patch samples/images/almalinux/almalinux-8.10 --follow | tee -a alma.log
./ib build samples/images/almalinux/almalinux-8.10 --follow | tee -a alma.log
./ib phase clean samples/images/almalinux/almalinux-8.10 --follow

#./ib phase base samples/images/almalinux/almalinux-9.8 --follow | tee -a alma.log
./ib phase patch samples/images/almalinux/almalinux-9.8 --follow | tee -a alma.log
./ib build samples/images/almalinux/almalinux-9.8 --follow | tee -a alma.log
./ib phase clean samples/images/almalinux/almalinux-9.8 --follow

#./ib phase base samples/images/almalinux/almalinux-10.2 --follow | tee -a alma.log
./ib phase patch samples/images/almalinux/almalinux-10.2 --follow | tee -a alma.log
./ib build samples/images/almalinux/almalinux-10.2 --follow | tee -a alma.log
./ib phase clean samples/images/almalinux/almalinux-10.2 --follow
