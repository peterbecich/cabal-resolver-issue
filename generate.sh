#!/bin/bash

for i in {1..400};
do mkdir package$i; 
cd package$i; 
cabal init;
var=$(shuf -n40 ../dependencies.txt | tr '\n' ',') && sed -i "s/base.*/$var base/g" package$i.cabal;
cd ..; 
done;
