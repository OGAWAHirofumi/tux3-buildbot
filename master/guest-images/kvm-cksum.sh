#!/bin/sh

for i in kvm-*.xz; do
    sha256sum $i > $i.sum
done
