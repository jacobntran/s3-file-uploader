#!/bin/bash

OBJECT=$1
S3_BUCKET=$2

if [ ! -e $OBJECT ]; then
    echo "File does not exist!"
    exit 1
fi

aws s3 cp $OBJECT s3://$S3_BUCKET
