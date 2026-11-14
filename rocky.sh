#!/bin/bash
>rockylinux.log

# ./ib phase base samples/images/rockylinux/rockylinux-9.8 --follow | tee -a rockylinux.log
# ./ib phase base samples/images/rockylinux/rockylinux-10.2 --follow | tee -a rockylinux.log

./ib phase patch samples/images/rockylinux/rockylinux-9.8 --follow | tee -a rockylinux.log
./ib phase patch samples/images/rockylinux/rockylinux-10.2 --follow | tee -a rockylinux.log

./ib build samples/images/rockylinux/rockylinux-9.8 --follow | tee -a rockylinux.log
./ib build samples/images/rockylinux/rockylinux-10.2 --follow | tee -a rockylinux.log

./ib phase clean samples/images/rockylinux/rockylinux-9.8 --follow
./ib phase clean samples/images/rockylinux/rockylinux-10.2 --follow